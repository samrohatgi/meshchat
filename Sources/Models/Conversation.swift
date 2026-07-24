import Foundation

struct Conversation: Identifiable, Codable {
    var id: UUID { peerID }
    let peerID: UUID
    var peerName: String
    var messages: [ChatMessage]

    var lastMessage: ChatMessage? { messages.last }

    var lastMessagePreview: String {
        guard let last = messages.last else { return "No messages yet" }
        return last.text
    }

    var lastMessageDate: Date {
        messages.last?.timestamp ?? .distantPast
    }
}
