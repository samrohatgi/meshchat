import Foundation
import MultipeerConnectivity
import Combine
#if canImport(UIKit)
import UIKit
#endif

/// Owns the MultipeerConnectivity stack (Bluetooth + peer-to-peer WiFi) and
/// implements simple flood/epidemic mesh relay on top of it.
///
///  - Every device both advertises itself and browses for others, and
///    auto-invites/accepts, so the mesh forms without user setup.
///  - 1:1 packets carry a stable `destinationID` (not MCPeerID, which
///    changes every session) plus a TTL, and are relayed hop-by-hop toward
///    that identity.
///  - Group packets carry a `groupID` instead and use broadcast semantics:
///    every node floods them onward to all its other connected peers.
///    Membership filtering (deciding whether a group packet is relevant)
///    is left to ChatStore, which knows which groups this device belongs
///    to. That's a deliberate simplification given there's no server to
///    hold real access control - documented as a known limitation.
///
/// This is intentionally simple (no routing tables) - fine for the size of
/// mesh this app is meant for.
final class MeshManager: NSObject, ObservableObject {

    // MARK: Published state

    @Published private(set) var connectedPeers: [MeshPeer] = []
    @Published private(set) var typingPeerIDs: Set<UUID> = []
    /// Last time we heard anything from a given peer identity - directly
    /// connected peers are "online"; everyone else shows "last seen".
    @Published private(set) var lastSeenByPeer: [UUID: Date] = [:]

    /// Every non-typing packet addressed to us (1:1) or broadcast as part
    /// of a group; ChatStore subscribes and decides what to do with it.
    let incomingPacket = PassthroughSubject<(packet: MeshPacket, hopCount: Int), Never>()

    // MARK: Identity

    /// Persistent identity for THIS device/user - survives app relaunches.
    let myID: UUID
    var myDisplayName: String {
        didSet { UserDefaults.standard.set(myDisplayName, forKey: Keys.displayName) }
    }

    // MARK: MultipeerConnectivity plumbing

    private let serviceType = "meshchat-p2p" // must be <=15 chars, lowercase+digits+hyphen
    private let localPeerID: MCPeerID
    private lazy var session: MCSession = {
        let s = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        return s
    }()
    private lazy var advertiser = MCNearbyServiceAdvertiser(peer: localPeerID, discoveryInfo: nil, serviceType: serviceType)
    private lazy var browser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: serviceType)

    // MCPeerID <-> stable identity, once we've completed the handshake with them
    private var identityByMCPeer: [MCPeerID: UUID] = [:]
    private var mcPeerByIdentity: [UUID: MCPeerID] = [:]
    private var nameByIdentity: [UUID: String] = [:]

    // Dedup cache so flood relay doesn't loop forever
    private var seenPacketIDs = Set<UUID>()
    private var seenPacketOrder: [UUID] = []
    private let seenCacheLimit = 500

    // Typing indicators auto-expire; track a clear-timer per peer.
    private var typingClearWork: [UUID: DispatchWorkItem] = [:]

    private enum Keys {
        static let myID = "meshchat.myID"
        static let displayName = "meshchat.displayName"
    }

    // MARK: Init

    override init() {
        if let saved = UserDefaults.standard.string(forKey: Keys.myID), let uuid = UUID(uuidString: saved) {
            myID = uuid
        } else {
            let fresh = UUID()
            UserDefaults.standard.set(fresh.uuidString, forKey: Keys.myID)
            myID = fresh
        }
        let savedName = UserDefaults.standard.string(forKey: Keys.displayName) ?? UIDeviceNameProvider.currentName()
        myDisplayName = savedName
        localPeerID = MCPeerID(displayName: savedName)
        super.init()
    }

    // MARK: Lifecycle

    func start() {
        advertiser.delegate = self
        browser.delegate = self
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
    }

    // MARK: Sending - chat messages

    /// Send a 1:1 chat message addressed to `destinationID`.
    @discardableResult
    func sendMessage(_ text: String, to destinationID: UUID, replyTo: (id: UUID, sender: String, text: String)?) -> UUID {
        let packet = MeshPacket(
            packetID: UUID(), type: .chatMessage, originID: myID, originName: myDisplayName,
            destinationID: destinationID, groupID: nil, text: text,
            targetMessageID: nil, reactionEmoji: nil, replyToMessageID: replyTo?.id,
            groupMemberIDs: nil, groupMemberNames: nil, ttl: MeshPacket.defaultTTL, timestamp: Date()
        )
        markSeen(packet.packetID)
        broadcast(packet, excluding: nil)
        return packet.packetID
    }

    /// Send a chat message to every member of a group (broadcast semantics).
    @discardableResult
    func sendGroupMessage(_ text: String, groupID: UUID, replyTo: (id: UUID, sender: String, text: String)?) -> UUID {
        let packet = MeshPacket(
            packetID: UUID(), type: .chatMessage, originID: myID, originName: myDisplayName,
            destinationID: nil, groupID: groupID, text: text,
            targetMessageID: nil, reactionEmoji: nil, replyToMessageID: replyTo?.id,
            groupMemberIDs: nil, groupMemberNames: nil, ttl: MeshPacket.defaultTTL, timestamp: Date()
        )
        markSeen(packet.packetID)
        broadcast(packet, excluding: nil)
        return packet.packetID
    }

    func createGroup(name: String, groupID: UUID, memberIDs: [UUID], memberNames: [UUID: String]) {
        var names: [String: String] = [:]
        for (id, name) in memberNames { names[id.uuidString] = name }
        let packet = MeshPacket(
            packetID: UUID(), type: .groupCreate, originID: myID, originName: myDisplayName,
            destinationID: nil, groupID: groupID, text: name,
            targetMessageID: nil, reactionEmoji: nil, replyToMessageID: nil,
            groupMemberIDs: memberIDs, groupMemberNames: names, ttl: MeshPacket.defaultTTL, timestamp: Date()
        )
        markSeen(packet.packetID)
        broadcast(packet, excluding: nil)
    }

    // MARK: Sending - receipts, reactions, edits, deletes

    func sendDeliveryAck(for messageID: UUID, to destinationID: UUID?, groupID: UUID?) {
        send(.deliveryAck, targetMessageID: messageID, to: destinationID, groupID: groupID)
    }

    func sendReadReceipt(for messageID: UUID, to destinationID: UUID?, groupID: UUID?) {
        send(.readReceipt, targetMessageID: messageID, to: destinationID, groupID: groupID)
    }

    func sendReaction(_ emoji: String?, on messageID: UUID, to destinationID: UUID?, groupID: UUID?) {
        send(.reaction, targetMessageID: messageID, reactionEmoji: emoji, to: destinationID, groupID: groupID)
    }

    func sendEdit(messageID: UUID, newText: String, to destinationID: UUID?, groupID: UUID?) {
        send(.editMessage, targetMessageID: messageID, text: newText, to: destinationID, groupID: groupID)
    }

    func sendDelete(messageID: UUID, to destinationID: UUID?, groupID: UUID?) {
        send(.deleteMessage, targetMessageID: messageID, to: destinationID, groupID: groupID)
    }

    private func send(_ type: PacketType, targetMessageID: UUID, text: String? = nil, reactionEmoji: String? = nil, to destinationID: UUID?, groupID: UUID?) {
        let packet = MeshPacket(
            packetID: UUID(), type: type, originID: myID, originName: myDisplayName,
            destinationID: destinationID, groupID: groupID, text: text,
            targetMessageID: targetMessageID, reactionEmoji: reactionEmoji, replyToMessageID: nil,
            groupMemberIDs: nil, groupMemberNames: nil, ttl: MeshPacket.defaultTTL, timestamp: Date()
        )
        markSeen(packet.packetID)
        broadcast(packet, excluding: nil)
    }

    // MARK: Sending - typing (ephemeral, direct peers only, not relayed)

    func sendTyping(_ isTyping: Bool, to destinationID: UUID) {
        guard let mcPeer = mcPeerByIdentity[destinationID] else { return }
        let packet = MeshPacket(
            packetID: UUID(), type: .typing, originID: myID, originName: myDisplayName,
            destinationID: destinationID, groupID: nil, text: isTyping ? "1" : "0",
            targetMessageID: nil, reactionEmoji: nil, replyToMessageID: nil,
            groupMemberIDs: nil, groupMemberNames: nil, ttl: 0, timestamp: Date()
        )
        guard let data = try? JSONEncoder().encode(packet) else { return }
        try? session.send(data, toPeers: [mcPeer], with: .unreliable)
    }

    // MARK: Handling incoming data

    private func handle(data: Data, from mcPeer: MCPeerID) {
        guard let packet = try? JSONDecoder().decode(MeshPacket.self, from: data) else { return }

        switch packet.type {
        case .identity:
            identityByMCPeer[mcPeer] = packet.originID
            mcPeerByIdentity[packet.originID] = mcPeer
            nameByIdentity[packet.originID] = packet.originName
            lastSeenByPeer[packet.originID] = Date()
            refreshConnectedPeersList()

        case .typing:
            let isTyping = packet.text == "1"
            nameByIdentity[packet.originID] = packet.originName
            if isTyping {
                typingPeerIDs.insert(packet.originID)
                scheduleTypingClear(for: packet.originID)
            } else {
                typingPeerIDs.remove(packet.originID)
                typingClearWork[packet.originID]?.cancel()
            }

        default:
            guard !seenPacketIDs.contains(packet.packetID) else { return }
            markSeen(packet.packetID)
            nameByIdentity[packet.originID] = packet.originName
            lastSeenByPeer[packet.originID] = Date()

            let hopCount = MeshPacket.defaultTTL - packet.ttl
            let isGroupPacket = packet.groupID != nil
            let isForMe = isGroupPacket || packet.destinationID == myID

            if isForMe {
                incomingPacket.send((packet, hopCount))
            }

            if isGroupPacket {
                // Broadcast semantics: always flood group packets onward.
                guard packet.ttl > 0 else { return }
                var forwarded = packet
                forwarded.ttl -= 1
                broadcast(forwarded, excluding: mcPeer)
            } else if packet.destinationID != myID {
                guard packet.ttl > 0 else { return }
                var forwarded = packet
                forwarded.ttl -= 1
                broadcast(forwarded, excluding: mcPeer)
            }
        }
    }

    private func scheduleTypingClear(for peerID: UUID) {
        typingClearWork[peerID]?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.typingPeerIDs.remove(peerID) }
        typingClearWork[peerID] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    private func broadcast(_ packet: MeshPacket, excluding excludedPeer: MCPeerID?) {
        guard let data = try? JSONEncoder().encode(packet) else { return }
        let targets = session.connectedPeers.filter { $0 != excludedPeer }
        guard !targets.isEmpty else { return }
        try? session.send(data, toPeers: targets, with: .reliable)
    }

    private func sendIdentity(to peers: [MCPeerID]) {
        let packet = MeshPacket(
            packetID: UUID(), type: .identity, originID: myID, originName: myDisplayName,
            destinationID: nil, groupID: nil, text: nil,
            targetMessageID: nil, reactionEmoji: nil, replyToMessageID: nil,
            groupMemberIDs: nil, groupMemberNames: nil, ttl: 0, timestamp: Date()
        )
        guard let data = try? JSONEncoder().encode(packet) else { return }
        try? session.send(data, toPeers: peers, with: .reliable)
    }

    private func markSeen(_ id: UUID) {
        seenPacketIDs.insert(id)
        seenPacketOrder.append(id)
        if seenPacketOrder.count > seenCacheLimit {
            let stale = seenPacketOrder.removeFirst()
            seenPacketIDs.remove(stale)
        }
    }

    private func refreshConnectedPeersList() {
        connectedPeers = session.connectedPeers.compactMap { mcPeer in
            guard let identity = identityByMCPeer[mcPeer] else { return nil }
            return MeshPeer(
                id: identity,
                displayName: nameByIdentity[identity] ?? mcPeer.displayName,
                mcPeerID: mcPeer,
                isConnectedDirectly: true,
                lastSeen: Date()
            )
        }
    }
}

// MARK: - MCSessionDelegate

extension MeshManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.sendIdentity(to: [peerID])
            case .notConnected:
                if let identity = self.identityByMCPeer[peerID] {
                    self.lastSeenByPeer[identity] = Date()
                    self.mcPeerByIdentity.removeValue(forKey: identity)
                }
                self.identityByMCPeer.removeValue(forKey: peerID)
                self.refreshConnectedPeersList()
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async { self.handle(data: data, from: peerID) }
    }

    // Unused but required by the protocol.
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MeshManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept everyone; this is an open mesh, like WhatsApp has no
        // per-connection approval step once you already have someone's number.
        invitationHandler(true, session)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MeshManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard !session.connectedPeers.contains(peerID) else { return }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        // MCSession will report didChange:.notConnected separately if the
        // link actually drops; nothing else required here.
    }
}

// MARK: - Device name helper

enum UIDeviceNameProvider {
    static func currentName() -> String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "MeshChat User"
        #endif
    }
}
