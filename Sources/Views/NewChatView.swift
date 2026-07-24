import SwiftUI

/// Lists devices currently visible over the mesh (direct Bluetooth/WiFi
/// range) so the user can start a new conversation with one.
struct NewChatView: View {
    @EnvironmentObject var mesh: MeshManager
    @Environment(\.dismiss) private var dismiss
    /// Called with the chosen peer; the parent is responsible for
    /// dismissing this sheet and pushing the chat in its own nav stack.
    var onSelect: (MeshPeer) -> Void

    var body: some View {
        NavigationStack {
            List {
                if mesh.connectedPeers.isEmpty {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Looking for nearby devices…")
                            .foregroundStyle(.secondary)
                        Text("Make sure Bluetooth and WiFi are on and the other person also has MeshChat open.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(mesh.connectedPeers) { peer in
                        Button {
                            onSelect(peer)
                            dismiss()
                        } label: {
                            HStack {
                                Circle().fill(Color.green).frame(width: 8, height: 8)
                                Text(peer.displayName)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("New Chat")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
