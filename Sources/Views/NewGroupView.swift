import SwiftUI

/// Multi-select nearby devices, name the group, and create it. The
/// membership + group name is broadcast to every selected peer as soon as
/// you tap Create - anyone not currently reachable will pick it up once
/// they reconnect to the mesh (the packet floods to everyone connected).
struct NewGroupView: View {
    @EnvironmentObject var mesh: MeshManager
    @EnvironmentObject var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    var onCreate: (UUID) -> Void

    @State private var selectedPeerIDs: Set<UUID> = []
    @State private var groupName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Group name") {
                    TextField("e.g. Weekend trip", text: $groupName)
                }
                Section("Members (\(selectedPeerIDs.count) selected)") {
                    if mesh.connectedPeers.isEmpty {
                        Text("No nearby devices yet. Keep this open while others come into range.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(mesh.connectedPeers) { peer in
                            Button {
                                if selectedPeerIDs.contains(peer.id) { selectedPeerIDs.remove(peer.id) }
                                else { selectedPeerIDs.insert(peer.id) }
                            } label: {
                                HStack {
                                    Text(peer.displayName).foregroundStyle(.primary)
                                    Spacer()
                                    if selectedPeerIDs.contains(peer.id) {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    } else {
                                        Image(systemName: "circle").foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let name = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
                        chatStore.createGroup(name: name.isEmpty ? "New group" : name, memberIDs: Array(selectedPeerIDs))
                        if let created = chatStore.conversations.last(where: { $0.isGroup }) {
                            dismiss()
                            onCreate(created.id)
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(selectedPeerIDs.isEmpty)
                }
            }
        }
    }
}
