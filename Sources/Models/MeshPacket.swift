import Foundation

/// Everything that travels over the mesh is one of these, serialized with
/// JSONEncoder before being handed to MCSession.

enum PacketType: String, Codable {
    case identity       // "hello, here's who I am" handshake
    case chatMessage     // an actual chat message (direct or to be relayed)
    case deliveryAck      // optional delivery confirmation back to sender
}

struct MeshPacket: Codable {
    let packetID: UUID          // unique per packet, used for relay dedup
    let type: PacketType
    let originID: UUID          // the persistent identity of whoever authored this
    let originName: String
    let destinationID: UUID?    // nil for identity/broadcast packets
    let text: String?
    var ttl: Int                // hops remaining; decremented at every relay
    let timestamp: Date

    /// Max hops a message is allowed to travel through the mesh before
    /// nodes stop relaying it. Keeps flood relay from looping forever.
    static let defaultTTL = 6
}
