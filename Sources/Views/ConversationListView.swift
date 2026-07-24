import SwiftUI

struct ConversationListView: View {
    @EnvironmentObject var mesh: MeshManager
    @EnvironmentObject var chatStore: ChatStore
    @State private var showingNewChat = false
    @State private var pendingNewPeer: MeshPeer?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Circle()
                            .fill(mesh.connectedPeers.isEmpty ? Color.gray : Color.green)
                            .frame(width: 8, height: 8)
                        Text(mesh.connectedPeers.isEmpty
                             ? "Searching for nearby devices…"
                             : "\(mesh.connectedPeers.count) device\(mesh.connectedPeers.count == 1 ? "" : "s") nearby")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Chats") {
                    if chatStore.conversations.isEmpty {
                        Text("No conversations yet. Tap + to message a nearby device.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(chatStore.conversations) { conversation in
                            NavigationLink {
                                ChatView(peerID: conversation.peerID, peerName: conversation.peerName)
                            } label: {
                                ConversationRow(conversation: conversation)
                            }
                        }
                    }
                }
            }
            .navigationTitle("MeshChat")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingNewChat = true } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showingNewChat) {
                NewChatView { peer in
                    pendingNewPeer = peer
                }
            }
            .navigationDestination(item: $pendingNewPeer) { peer in
                ChatView(peerID: peer.id, peerName: peer.displayName)
            }
        }
    }
}

private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.green.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(Text(initials).font(.headline).foregroundStyle(.green))

            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.peerName).font(.body.weight(.medium))
                Text(conversation.lastMessagePreview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let last = conversation.lastMessage {
                Text(last.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var initials: String {
        let parts = conversation.peerName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}
