import Foundation

/// Everything that travels over the mesh is one of these, serialized with
/// JSONEncoder before being handed to MCSession.

enum PacketType: String, Codable {
    case identity           // "hello, here's who I am" handshake
    case chatMessage        // a text message (1:1 or group)
    case deliveryAck        // "I received this message" (sending -> sentDirect/relayed)
    case readReceipt        // "I've read this message" (-> read)
    case typing             // ephemeral "I'm typing" indicator, direct peers only
    case reaction           // add/remove an emoji reaction on a message
    case editMessage        // replace a message's text
    case deleteMessage      // delete a message for everyone
    case groupCreate        // announce a new group and its membership
}

struct MeshPacket: Codable {
    let packetID: UUID            // unique per packet, used for relay dedup
    let type: PacketType
    let originID: UUID            // persistent identity of whoever authored this
    let originName: String
    let photoData: Data?          // small JPEG thumbnail, .identity packets only; nil = no photo set
    let destinationID: UUID?      // set for 1:1 packets; nil for group/broadcast packets
    let groupID: UUID?            // set for packets that belong to a group conversation
    let text: String?             // message text, edited text, or group name
    let targetMessageID: UUID?    // message being acked/read/reacted to/edited/deleted
    let reactionEmoji: String?    // emoji for .reaction; nil means "remove my reaction"
    let replyToMessageID: UUID?   // message this chatMessage is replying to
    let groupMemberIDs: [UUID]?   // membership for .groupCreate
    let groupMemberNames: [String: String]?  // uuidString -> display name, for .groupCreate
    var ttl: Int                  // hops remaining; decremented at every relay
    let timestamp: Date

    /// Max hops a message is allowed to travel through the mesh before
    /// nodes stop relaying it. Keeps flood relay from looping forever.
    static let defaultTTL = 6
}
