import Foundation
import Combine

/// All chat state lives here, keyed by peer identity (not MCPeerID, which
/// isn't stable). Persists to a JSON file in the app's Documents directory,
/// so history survives relaunches - no server, no iCloud, fully offline.
final class ChatStore: ObservableObject {
    @Published private(set) var conversations: [Conversation] = []

    private let mesh: MeshManager
    private var cancellables = Set<AnyCancellable>()
    private let fileURL: URL

    init(mesh: MeshManager) {
        self.mesh = mesh
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = docs.appendingPathComponent("meshchat_conversations.json")
        load()
        observeIncomingMessages()
    }

    // MARK: Sending

    func sendMessage(_ text: String, to peer: MeshPeer) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let message = ChatMessage(
            id: UUID(),
            senderID: mesh.myID,
            senderName: mesh.myDisplayName,
            text: trimmed,
            timestamp: Date(),
            isOutgoing: true,
            deliveryState: .sending,
            hopCount: 0
        )
        append(message, peerID: peer.id, peerName: peer.displayName)
        mesh.send(text: trimmed, to: peer.id)

        // Optimistic delivery state: MultipeerConnectivity's .reliable mode
        // guarantees in-order delivery to directly connected peers, but we
        // don't get a network-level ack, so we mark it sent once handed off.
        markLatestState(.sentDirect, peerID: peer.id, messageID: message.id)
    }

    // MARK: Receiving

    private func observeIncomingMessages() {
        mesh.incomingMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                let message = ChatMessage(
                    id: UUID(),
                    senderID: event.originID,
                    senderName: event.originName,
                    text: event.text,
                    timestamp: event.timestamp,
                    isOutgoing: false,
                    deliveryState: event.hopCount > 0 ? .relayed : .sentDirect,
                    hopCount: event.hopCount
                )
                self.append(message, peerID: event.originID, peerName: event.originName)
            }
            .store(in: &cancellables)
    }

    // MARK: Mutation helpers

    private func append(_ message: ChatMessage, peerID: UUID, peerName: String) {
        if let idx = conversations.firstIndex(where: { $0.peerID == peerID }) {
            conversations[idx].messages.append(message)
            conversations[idx].peerName = peerName // keep name fresh
        } else {
            conversations.append(Conversation(peerID: peerID, peerName: peerName, messages: [message]))
        }
        sortConversations()
        save()
    }

    private func markLatestState(_ state: DeliveryState, peerID: UUID, messageID: UUID) {
        guard let convIdx = conversations.firstIndex(where: { $0.peerID == peerID }),
              let msgIdx = conversations[convIdx].messages.firstIndex(where: { $0.id == messageID }) else { return }
        conversations[convIdx].messages[msgIdx].deliveryState = state
        save()
    }

    private func sortConversations() {
        conversations.sort { $0.lastMessageDate > $1.lastMessageDate }
    }

    /// Finds or creates a conversation shell for a peer you've just
    /// discovered/connected to but haven't messaged yet, so it can show up
    /// in "Start chat" pickers.
    func conversation(for peer: MeshPeer) -> Conversation {
        if let existing = conversations.first(where: { $0.peerID == peer.id }) {
            return existing
        }
        return Conversation(peerID: peer.id, peerName: peer.displayName, messages: [])
    }

    // MARK: Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Conversation].self, from: data) else { return }
        conversations = decoded
        sortConversations()
    }
}
