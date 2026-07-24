import Foundation
import MultipeerConnectivity
import Combine
#if canImport(UIKit)
import UIKit
#endif

/// Owns the MultipeerConnectivity stack (Bluetooth + peer-to-peer WiFi) and
/// implements simple flood/epidemic mesh relay on top of it:
///
///  - Every device both advertises itself and browses for others, and
///    auto-invites/accepts, so the mesh forms without user setup.
///  - Messages carry a stable `originID`/`destinationID` (not MCPeerID,
///    which changes every session) plus a TTL.
///  - When a node receives a chatMessage packet that isn't addressed to it,
///    and hasn't seen that packetID before, it decrements TTL and forwards
///    it to all its other connected peers. This lets messages hop across
///    multiple phones to reach someone outside direct Bluetooth range.
///
/// This is intentionally simple (no routing tables) - fine for the size of
/// mesh this app is meant for. It trades some redundant traffic for
/// reliability and zero configuration.
final class MeshManager: NSObject, ObservableObject {

    // MARK: Published state

    @Published private(set) var connectedPeers: [MeshPeer] = []
    @Published private(set) var isAdvertising = false
    @Published private(set) var isBrowsing = false
    /// A message arrived; ChatStore listens to this and files it away.
    let incomingMessage = PassthroughSubject<(originID: UUID, originName: String, text: String, hopCount: Int, timestamp: Date), Never>()

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

    // MCPeerID -> stable identity, once we've completed the handshake with them
    private var identityByMCPeer: [MCPeerID: UUID] = [:]
    private var nameByIdentity: [UUID: String] = [:]

    // Dedup cache so flood relay doesn't loop forever
    private var seenPacketIDs = Set<UUID>()
    private var seenPacketOrder: [UUID] = []
    private let seenCacheLimit = 500

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
        isAdvertising = true
        isBrowsing = true
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        isAdvertising = false
        isBrowsing = false
    }

    // MARK: Sending

    /// Send a chat message addressed to `destinationID`. If we're directly
    /// connected to them it goes straight there; otherwise it's flooded to
    /// all connected peers so the mesh can relay it onward.
    func send(text: String, to destinationID: UUID) {
        let packet = MeshPacket(
            packetID: UUID(),
            type: .chatMessage,
            originID: myID,
            originName: myDisplayName,
            destinationID: destinationID,
            text: text,
            ttl: MeshPacket.defaultTTL,
            timestamp: Date()
        )
        markSeen(packet.packetID)
        broadcast(packet, excluding: nil)
    }

    // MARK: Handling incoming data

    private func handle(data: Data, from mcPeer: MCPeerID) {
        guard let packet = try? JSONDecoder().decode(MeshPacket.self, from: data) else { return }

        switch packet.type {
        case .identity:
            identityByMCPeer[mcPeer] = packet.originID
            nameByIdentity[packet.originID] = packet.originName
            refreshConnectedPeersList()

        case .chatMessage:
            guard !seenPacketIDs.contains(packet.packetID) else { return }
            markSeen(packet.packetID)
            nameByIdentity[packet.originID] = packet.originName

            let hopCount = MeshPacket.defaultTTL - packet.ttl
            if packet.destinationID == myID {
                incomingMessage.send((packet.originID, packet.originName, packet.text ?? "", hopCount, packet.timestamp))
            } else {
                // Not for us - relay onward if it still has hops left.
                guard packet.ttl > 0 else { return }
                var forwarded = packet
                forwarded.ttl -= 1
                broadcast(forwarded, excluding: mcPeer)
            }

        case .deliveryAck:
            break // reserved for future read-receipt support
        }
    }

    private func broadcast(_ packet: MeshPacket, excluding excludedPeer: MCPeerID?) {
        guard let data = try? JSONEncoder().encode(packet) else { return }
        let targets = session.connectedPeers.filter { $0 != excludedPeer }
        guard !targets.isEmpty else { return }
        try? session.send(data, toPeers: targets, with: .reliable)
    }

    private func sendIdentity(to peers: [MCPeerID]) {
        let packet = MeshPacket(
            packetID: UUID(),
            type: .identity,
            originID: myID,
            originName: myDisplayName,
            destinationID: nil,
            text: nil,
            ttl: 0,
            timestamp: Date()
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
        // Auto-invite. Avoid duplicate invites to already-connected peers.
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
