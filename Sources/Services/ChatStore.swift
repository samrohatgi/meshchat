import Foundation
import Combine

/// All chat state lives here, keyed by conversation identity (a peer's
/// persistent ID for 1:1 chats, or a group's own UUID for groups).
/// Persists to JSON files in the app's Documents directory - no server,
/// no iCloud, fully offline.
final class ChatStore: ObservableObject {
    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var blockedPeerIDs: Set<UUID> = []

    private let mesh: MeshManager
    private var cancellables = Set<AnyCancellable>()
    private let conversationsFileURL: URL
    private let blockedFileURL: URL

    /// Best-known display name for anyone we've ever seen a packet or
    /// group roster entry from - lets group member lists render names for
    /// people we haven't directly connected to yet.
    private var peerNameDirectory: [UUID: String] = [:]

    init(mesh: MeshManager) {
        self.mesh = mesh
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.conversationsFileURL = docs.appendingPathComponent("meshchat_conversations.json")
        self.blockedFileURL = docs.appendingPathComponent("meshchat_blocked.json")
        load()
        observeIncoming()
    }

    // MARK: Sending

    func sendMessage(_ text: String, to conversation: Conversation, replyTo: ChatMessage?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let replyInfo = replyTo.map { (id: $0.id, sender: $0.senderName, text: $0.displayText) }
        let messageID: UUID
        if conversation.isGroup {
            messageID = mesh.sendGroupMessage(trimmed, groupID: conversation.id, replyTo: replyInfo)
        } else {
            messageID = mesh.sendMessage(trimmed, to: conversation.id, replyTo: replyInfo)
        }

        let message = ChatMessage(
            id: messageID, senderID: mesh.myID, senderName: mesh.myDisplayName, text: trimmed,
            timestamp: Date(), isOutgoing: true, deliveryState: .sentDirect, hopCount: 0,
            replyToMessageID: replyTo?.id, replyPreviewText: replyTo?.displayText, replyPreviewSender: replyTo?.senderName
        )
        append(message, to: conversation.id, defaultTitle: conversation.title, isGroup: conversation.isGroup, memberIDs: conversation.memberIDs)
    }

    func createGroup(name: String, memberIDs: [UUID]) {
        let groupID = UUID()
        var names: [UUID: String] = [mesh.myID: mesh.myDisplayName]
        for id in memberIDs { names[id] = displayName(for: id) }
        let allMembers = [mesh.myID] + memberIDs

        mesh.createGroup(name: name, groupID: groupID, memberIDs: allMembers, memberNames: names)
        conversations.append(Conversation(id: groupID, title: name, messages: [], isGroup: true, memberIDs: allMembers))
        sortConversations()
        save()
    }

    /// Marks every unread incoming message in this conversation read, and
    /// tells the senders so (read receipts).
    func markAsRead(_ conversation: Conversation) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        conversations[idx].lastReadAt = Date()
        for message in conversations[idx].messages where !message.isOutgoing && !message.readBy.contains(mesh.myID) {
            mesh.sendReadReceipt(
                for: message.id,
                to: conversation.isGroup ? nil : conversation.id,
                groupID: conversation.isGroup ? conversation.id : nil
            )
        }
        save()
    }

    func setTyping(_ isTyping: Bool, in conversation: Conversation) {
        guard !conversation.isGroup else { return } // keep typing indicators 1:1 for simplicity
        mesh.sendTyping(isTyping, to: conversation.id)
    }

    // MARK: Message actions

    func toggleStar(_ message: ChatMessage, in conversation: Conversation) {
        mutate(messageID: message.id, in: conversation.id) { $0.isStarred.toggle() }
    }

    func deleteForMe(_ message: ChatMessage, in conversation: Conversation) {
        guard let cIdx = conversations.firstIndex(where: { $0.id == conversation.id }),
              let mIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == message.id }) else { return }
        conversations[cIdx].messages.remove(at: mIdx)
        save()
    }

    func deleteForEveryone(_ message: ChatMessage, in conversation: Conversation) {
        mutate(messageID: message.id, in: conversation.id) {
            $0.isDeletedForEveryone = true
            $0.text = ""
        }
        mesh.sendDelete(
            messageID: message.id,
            to: conversation.isGroup ? nil : conversation.id,
            groupID: conversation.isGroup ? conversation.id : nil
        )
    }

    func editMyMessage(_ message: ChatMessage, newText: String, in conversation: Conversation) {
        guard message.isOutgoing else { return }
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate(messageID: message.id, in: conversation.id) {
            $0.text = trimmed
            $0.isEdited = true
        }
        mesh.sendEdit(
            messageID: message.id, newText: trimmed,
            to: conversation.isGroup ? nil : conversation.id,
            groupID: conversation.isGroup ? conversation.id : nil
        )
    }

    func react(_ emoji: String?, to message: ChatMessage, in conversation: Conversation) {
        mutate(messageID: message.id, in: conversation.id) {
            if let emoji { $0.reactions[mesh.myID.uuidString] = emoji }
            else { $0.reactions.removeValue(forKey: mesh.myID.uuidString) }
        }
        mesh.sendReaction(
            emoji, on: message.id,
            to: conversation.isGroup ? nil : conversation.id,
            groupID: conversation.isGroup ? conversation.id : nil
        )
    }

    func forward(_ message: ChatMessage, to targetConversation: Conversation) {
        sendMessage(message.displayText, to: targetConversation, replyTo: nil)
    }

    var starredMessages: [(conversation: Conversation, message: ChatMessage)] {
        conversations
            .flatMap { conv in conv.messages.filter { $0.isStarred }.map { (conv, $0) } }
            .sorted { $0.message.timestamp > $1.message.timestamp }
    }

    func search(_ query: String) -> [(conversation: Conversation, message: ChatMessage)] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return conversations
            .flatMap { conv in conv.messages.filter { !$0.isDeletedForEveryone && $0.text.localizedCaseInsensitiveContains(q) }.map { (conv, $0) } }
            .sorted { $0.message.timestamp > $1.message.timestamp }
    }

    // MARK: Conversation settings

    func setMuted(_ muted: Bool, for conversation: Conversation) {
        updateConversation(conversation.id) { $0.isMuted = muted }
    }

    func setArchived(_ archived: Bool, for conversation: Conversation) {
        updateConversation(conversation.id) { $0.isArchived = archived }
    }

    func setPinned(_ pinned: Bool, for conversation: Conversation) {
        updateConversation(conversation.id) { $0.isPinned = pinned }
    }

    // MARK: Blocking

    func block(_ peerID: UUID) { blockedPeerIDs.insert(peerID); saveBlocked() }
    func unblock(_ peerID: UUID) { blockedPeerIDs.remove(peerID); saveBlocked() }
    func isBlocked(_ peerID: UUID) -> Bool { blockedPeerIDs.contains(peerID) }

    // MARK: Names

    func displayName(for peerID: UUID) -> String {
        if peerID == mesh.myID { return "You" }
        if let known = mesh.connectedPeers.first(where: { $0.id == peerID })?.displayName { return known }
        return peerNameDirectory[peerID] ?? "Unknown"
    }

    /// Finds or creates a conversation shell for a peer you've just
    /// discovered/connected to but haven't messaged yet.
    func conversation(for peer: MeshPeer) -> Conversation {
        if let existing = conversations.first(where: { $0.id == peer.id }) { return existing }
        return Conversation(id: peer.id, title: peer.displayName, messages: [], isGroup: false, memberIDs: [peer.id])
    }

    // MARK: Receiving

    private func observeIncoming() {
        mesh.incomingPacket
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in self?.handle(event.packet, hopCount: event.hopCount) }
            .store(in: &cancellables)
    }

    private func handle(_ packet: MeshPacket, hopCount: Int) {
        peerNameDirectory[packet.originID] = packet.originName

        switch packet.type {
        case .identity, .typing:
            break // handled directly inside MeshManager

        case .chatMessage:
            handleChatMessage(packet, hopCount: hopCount)

        case .deliveryAck:
            mutate(messageID: packet.targetMessageID, in: conversationID(for: packet)) { message in
                guard message.deliveryState != .read else { return }
                message.deliveryState = hopCount > 0 ? .relayed : .sentDirect
            }

        case .readReceipt:
            mutate(messageID: packet.targetMessageID, in: conversationID(for: packet)) { message in
                message.readBy.insert(packet.originID)
                if message.isOutgoing { message.deliveryState = .read }
            }

        case .reaction:
            mutate(messageID: packet.targetMessageID, in: conversationID(for: packet)) { message in
                if let emoji = packet.reactionEmoji { message.reactions[packet.originID.uuidString] = emoji }
                else { message.reactions.removeValue(forKey: packet.originID.uuidString) }
            }

        case .editMessage:
            mutate(messageID: packet.targetMessageID, in: conversationID(for: packet)) { message in
                message.text = packet.text ?? message.text
                message.isEdited = true
            }

        case .deleteMessage:
            mutate(messageID: packet.targetMessageID, in: conversationID(for: packet)) { message in
                message.isDeletedForEveryone = true
                message.text = ""
            }

        case .groupCreate:
            handleGroupCreate(packet)
        }
    }

    private func handleChatMessage(_ packet: MeshPacket, hopCount: Int) {
        guard !isBlocked(packet.originID) else { return }
        let convID = packet.groupID ?? packet.originID

        if packet.groupID != nil {
            // Only accept group messages for groups we actually know we're in.
            guard conversations.contains(where: { $0.id == convID }) else { return }
        }

        var message = ChatMessage(
            id: packet.packetID, senderID: packet.originID, senderName: packet.originName,
            text: packet.text ?? "", timestamp: packet.timestamp, isOutgoing: false,
            deliveryState: hopCount > 0 ? .relayed : .sentDirect, hopCount: hopCount,
            replyToMessageID: packet.replyToMessageID
        )
        if let replyID = packet.replyToMessageID,
           let conv = conversations.first(where: { $0.id == convID }),
           let original = conv.messages.first(where: { $0.id == replyID }) {
            message.replyPreviewText = original.displayText
            message.replyPreviewSender = original.senderName
        }

        if packet.groupID != nil {
            append(message, to: convID, defaultTitle: "Group", isGroup: true, memberIDs: [])
        } else {
            append(message, to: convID, defaultTitle: packet.originName, isGroup: false, memberIDs: [convID])
        }

        mesh.sendDeliveryAck(
            for: packet.packetID,
            to: packet.groupID == nil ? packet.originID : nil,
            groupID: packet.groupID
        )
    }

    private func handleGroupCreate(_ packet: MeshPacket) {
        guard let groupID = packet.groupID, let memberIDs = packet.groupMemberIDs else { return }
        guard memberIDs.contains(mesh.myID) else { return } // only join groups we're actually in

        for (idString, name) in packet.groupMemberNames ?? [:] {
            if let id = UUID(uuidString: idString) { peerNameDirectory[id] = name }
        }

        if let idx = conversations.firstIndex(where: { $0.id == groupID }) {
            conversations[idx].title = packet.text ?? conversations[idx].title
            conversations[idx].memberIDs = memberIDs
        } else {
            conversations.append(Conversation(id: groupID, title: packet.text ?? "Group", messages: [], isGroup: true, memberIDs: memberIDs))
            sortConversations()
        }
        save()
    }

    private func conversationID(for packet: MeshPacket) -> UUID {
        packet.groupID ?? packet.originID
    }

    // MARK: Mutation helpers

    private func append(_ message: ChatMessage, to conversationID: UUID, defaultTitle: String, isGroup: Bool, memberIDs: [UUID]) {
        if let idx = conversations.firstIndex(where: { $0.id == conversationID }) {
            conversations[idx].messages.append(message)
            if !isGroup { conversations[idx].title = defaultTitle }
        } else {
            conversations.append(Conversation(id: conversationID, title: defaultTitle, messages: [message], isGroup: isGroup, memberIDs: memberIDs))
        }
        sortConversations()
        save()
    }

    private func mutate(messageID: UUID?, in conversationID: UUID, _ transform: (inout ChatMessage) -> Void) {
        guard let messageID,
              let cIdx = conversations.firstIndex(where: { $0.id == conversationID }),
              let mIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == messageID }) else { return }
        transform(&conversations[cIdx].messages[mIdx])
        save()
    }

    private func updateConversation(_ id: UUID, _ transform: (inout Conversation) -> Void) {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        transform(&conversations[idx])
        save()
    }

    private func sortConversations() {
        conversations.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.lastMessageDate > rhs.lastMessageDate
        }
    }

    // MARK: Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        try? data.write(to: conversationsFileURL, options: .atomic)
    }

    private func load() {
        if let data = try? Data(contentsOf: conversationsFileURL),
           let decoded = try? JSONDecoder().decode([Conversation].self, from: data) {
            conversations = decoded
            sortConversations()
        }
        if let data = try? Data(contentsOf: blockedFileURL),
           let decoded = try? JSONDecoder().decode([UUID].self, from: data) {
            blockedPeerIDs = Set(decoded)
        }
    }

    private func saveBlocked() {
        guard let data = try? JSONEncoder().encode(Array(blockedPeerIDs)) else { return }
        try? data.write(to: blockedFileURL, options: .atomic)
    }
}
