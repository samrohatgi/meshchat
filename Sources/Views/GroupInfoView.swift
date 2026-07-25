import SwiftUI

/// Group name + member roster, resolved through ChatStore's name directory
/// so it works even for members you haven't directly connected to yet.
struct GroupInfoView: View {
    let conversationID: UUID

    @EnvironmentObject var mesh: MeshManager
    @EnvironmentObject var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss

    private var conversation: Conversation? {
        chatStore.conversations.first(where: { $0.id == conversationID })
    }

    private func initials(for memberID: UUID) -> String {
        let parts = chatStore.displayName(for: memberID).split(separator: " ")
        return String(parts.prefix(2).compactMap { $0.first }).uppercased()
    }

    var body: some View {
        NavigationStack {
            List {
                if let conversation {
                    Section {
                        VStack(spacing: 8) {
                            Circle()
                                .fill(Color.blue.opacity(0.15))
                                .frame(width: 72, height: 72)
                                .overlay(Image(systemName: "person.3.fill").font(.title).foregroundStyle(.blue))
                            Text(conversation.title).font(.title3.weight(.semibold))
                            Text("\(conversation.memberIDs.count) members")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .listRowBackground(Color.clear)
                    }

                    Section("Members") {
                        ForEach(conversation.memberIDs, id: \.self) { memberID in
                            HStack {
                                AvatarView(
                                    photoData: memberID == mesh.myID ? mesh.myPhotoData : mesh.photoByIdentity[memberID],
                                    initials: initials(for: memberID), tint: .green, size: 32
                                )
                                Text(chatStore.displayName(for: memberID))
                                Spacer()
                                if mesh.connectedPeers.contains(where: { $0.id == memberID }) {
                                    Circle().fill(Color.green).frame(width: 8, height: 8)
                                }
                            }
                        }
                    }

                    Section {
                        Button {
                            chatStore.setMuted(!conversation.isMuted, for: conversation)
                        } label: {
                            Label(conversation.isMuted ? "Unmute group" : "Mute group", systemImage: conversation.isMuted ? "bell" : "bell.slash")
                        }
                        Button {
                            chatStore.setPinned(!conversation.isPinned, for: conversation)
                        } label: {
                            Label(conversation.isPinned ? "Unpin group" : "Pin group", systemImage: "pin")
                        }
                        Button(role: .destructive) {
                            chatStore.setArchived(true, for: conversation)
                            dismiss()
                        } label: {
                            Label("Archive group", systemImage: "archivebox")
                        }
                    }
                } else {
                    Text("Group not found.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Group info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
