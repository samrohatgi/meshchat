import Foundation

enum DeliveryState: String, Codable {
    case sending
    case sentDirect      // delivered over a direct connection
    case relayed         // delivered via one or more mesh hops
    case failed
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let senderID: UUID
    let senderName: String
    let text: String
    let timestamp: Date
    var isOutgoing: Bool
    var deliveryState: DeliveryState
    var hopCount: Int   // 0 = direct, >0 = number of mesh relays it passed through
}
