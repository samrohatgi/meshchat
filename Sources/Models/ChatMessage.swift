import Foundation

enum DeliveryState: String, Codable {
    case sending
    case sentDirect      // handed off over a direct connection
    case relayed          // delivered via one or more mesh hops
    case read              // recipient has opened the chat and seen it
    case failed
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let senderID: UUID
    let senderName: String
    var text: String
    let timestamp: Date
    var isOutgoing: Bool
    var deliveryState: DeliveryState
    var hopCount: Int              // 0 = direct, >0 = number of mesh relays it passed through

    var replyToMessageID: UUID?
    var replyPreviewText: String?  // snapshot of the quoted message, so it still shows if that message is later deleted
    var replyPreviewSender: String?

    /// senderID.uuidString -> emoji. A dictionary so each person has at most one reaction.
    var reactions: [String: String] = [:]

    var isEdited: Bool = false
    var isDeletedForEveryone: Bool = false
    var isStarred: Bool = false

    /// Group chats only: who has read this message so far (by persistent identity).
    var readBy: Set<UUID> = []

    var displayText: String {
        isDeletedForEveryone ? "This message was deleted" : text
    }
}
