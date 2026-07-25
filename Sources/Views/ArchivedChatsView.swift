import SwiftUI

struct ArchivedChatsView: View {
    @EnvironmentObject var mesh: MeshManager
    @EnvironmentObject var chatStore: ChatStore

    private var archived: [Conversation] {
        chatStore.conversations.filter { $0.isArchived }.sorted { $0.lastMessageDate > $1.lastMessageDate }
    }

    var body: some View {
        List {
            if archived.isEmpty {
                Text("No archived chats.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(archived) { conversation in
                    NavigationLink {
                        ChatView(conversationID: conversation.id)
                    } label: {
                        ConversationRow(conversation: conversation, isOnline: mesh.connectedPeers.contains(where: { $0.id == conversation.id }))
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            chatStore.setArchived(false, for: conversation)
                        } label: {
                            Label("Unarchive", systemImage: "tray.and.arrow.up")
                        }
                        .tint(.green)
                    }
                }
            }
        }
        .navigationTitle("Archived")
    }
}
