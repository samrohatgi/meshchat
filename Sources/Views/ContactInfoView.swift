import SwiftUI

/// 1:1 contact detail sheet: online/last-seen status plus block/unblock,
/// mirroring WhatsApp's contact info screen (minus anything media-related).
struct ContactInfoView: View {
    let peerID: UUID

    @EnvironmentObject var mesh: MeshManager
    @EnvironmentObject var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var showingBlockConfirm = false

    private var isOnline: Bool {
        mesh.connectedPeers.contains(where: { $0.id == peerID })
    }

    private var lastSeenText: String {
        guard !isOnline else { return "Online now" }
        guard let last = mesh.lastSeenByPeer[peerID] else { return "Not seen yet on this mesh" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Last seen \(formatter.localizedString(for: last, relativeTo: Date()))"
    }

    private var isBlocked: Bool {
        chatStore.isBlocked(peerID)
    }

    private var initials: String {
        let parts = chatStore.displayName(for: peerID).split(separator: " ")
        return String(parts.prefix(2).compactMap { $0.first }).uppercased()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        AvatarView(photoData: mesh.photoByIdentity[peerID], initials: initials, tint: .green, size: 72)
                        Text(chatStore.displayName(for: peerID)).font(.title3.weight(.semibold))
                        HStack(spacing: 4) {
                            Circle().fill(isOnline ? Color.green : Color.gray).frame(width: 7, height: 7)
                            Text(lastSeenText).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Button(role: .destructive) {
                        showingBlockConfirm = true
                    } label: {
                        Label(isBlocked ? "Unblock contact" : "Block contact", systemImage: isBlocked ? "checkmark.circle" : "hand.raised.fill")
                    }
                }
            }
            .navigationTitle("Contact info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                isBlocked ? "Unblock this contact?" : "Block this contact?",
                isPresented: $showingBlockConfirm,
                titleVisibility: .visible
            ) {
                Button(isBlocked ? "Unblock" : "Block", role: .destructive) {
                    if isBlocked { chatStore.unblock(peerID) } else { chatStore.block(peerID) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(isBlocked
                     ? "You'll be able to receive messages from them again."
                     : "Blocked contacts can't send you messages, and the mesh will drop packets that originate from them.")
            }
        }
    }
}
