import Foundation
import MultipeerConnectivity

/// A device we've discovered or connected to over the mesh.
struct MeshPeer: Identifiable, Hashable {
    /// Stable identity that survives reconnects (unlike MCPeerID, which the
    /// OS re-creates each session). Exchanged during the handshake.
    let id: UUID
    var displayName: String
    var mcPeerID: MCPeerID?
    var isConnectedDirectly: Bool
    var lastSeen: Date

    static func == (lhs: MeshPeer, rhs: MeshPeer) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
