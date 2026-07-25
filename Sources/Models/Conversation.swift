import Foundation

/// One conversation - either 1:1 with a peer, or a group. `id` is the
/// peer's persistent identity for 1:1 chats, or the group's own UUID for
/// group chats, so it works as a stable dictionary/list key either way.
struct Conversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]

    var isGroup: Bool
    /// For groups: every member's persistent ID, including yourself.
    /// For 1:1: just the peer's ID.
    var memberIDs: [UUID]

    var isMuted: Bool = false
    var isArchived: Bool = false
    var isPinned: Bool = false

    /// Local-only: last time you opened this conversation. Used to compute
    /// the unread badge (messages with a later timestamp than this).
    var lastReadAt: Date = .distantPast

    var lastMessage: ChatMessage? { messages.last(where: { !$0.isDeletedForEveryone }) ?? messages.last }

    var lastMessagePreview: String {
        guard let last = messages.last else { return "No messages yet" }
        return last.displayText
    }

    var lastMessageDate: Date {
        messages.last?.timestamp ?? .distantPast
    }

    var unreadCount: Int {
        messages.filter { !$0.isOutgoing && $0.timestamp > lastReadAt }.count
    }
}
