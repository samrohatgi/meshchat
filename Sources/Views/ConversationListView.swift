import SwiftUI

struct ConversationListView: View {
    @EnvironmentObject var mesh: MeshManager
    @EnvironmentObject var chatStore: ChatStore
    @State private var showingNewChat = false
    @State private var showingNewGroup = false
    @State private var showingProfile = false
    @State private var pendingNewPeer: MeshPeer?
    @State private var openConversationID: UUID?

    private var pinned: [Conversation] { chatStore.conversations.filter { $0.isPinned && !$0.isArchived } }
    private var regular: [Conversation] { chatStore.conversations.filter { !$0.isPinned && !$0.isArchived } }
    private var archivedCount: Int { chatStore.conversations.filter { $0.isArchived }.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showingProfile = true } label: {
                        HStack(spacing: 12) {
                            AvatarView(photoData: mesh.myPhotoData, initials: myInitials, tint: .green, size: 44)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(mesh.myDisplayName).font(.body.weight(.medium)).foregroundStyle(.primary)
                                Text("Tap to edit your profile").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }

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

                    NavigationLink { StarredMessagesView() } label: {
                        Label("Starred messages", systemImage: "star")
                    }
                    if archivedCount > 0 {
                        NavigationLink { ArchivedChatsView() } label: {
                            HStack {
                                Label("Archived", systemImage: "archivebox")
                                Spacer()
                                Text("\(archivedCount)").foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !pinned.isEmpty {
                    Section("Pinned") {
                        ForEach(pinned) { conversation in
                            conversationRow(conversation)
                        }
                    }
                }

                Section("Chats") {
                    if regular.isEmpty && pinned.isEmpty {
                        Text("No conversations yet. Tap + to message a nearby device.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(regular) { conversation in
                            conversationRow(conversation)
                        }
                    }
                }
            }
            .navigationTitle("MeshChat")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { showingNewChat = true } label: { Label("New chat", systemImage: "message") }
                        Button { showingNewGroup = true } label: { Label("New group", systemImage: "person.3") }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showingNewChat) {
                NewChatView { peer in pendingNewPeer = peer }
            }
            .sheet(isPresented: $showingNewGroup) {
                NewGroupView { groupID in openConversationID = groupID }
            }
            .sheet(isPresented: $showingProfile) { ProfileView() }
            .navigationDestination(item: $pendingNewPeer) { peer in
                ChatView(conversationID: peer.id)
            }
            .navigationDestination(item: $openConversationID) { id in
                ChatView(conversationID: id)
            }
        }
    }

    private var myInitials: String {
        let parts = mesh.myDisplayName.split(separator: " ")
        return String(parts.prefix(2).compactMap { $0.first }).uppercased()
    }

    @ViewBuilder
    private func conversationRow(_ conversation: Conversation) -> some View {
        NavigationLink {
            ChatView(conversationID: conversation.id)
        } label: {
            ConversationRow(
                conversation: conversation,
                isOnline: mesh.connectedPeers.contains(where: { $0.id == conversation.id }),
                photoData: conversation.isGroup ? nil : mesh.photoByIdentity[conversation.id]
            )
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                chatStore.setArchived(true, for: conversation)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .tint(.gray)
        }
        .swipeActions(edge: .leading) {
            Button {
                chatStore.setPinned(!conversation.isPinned, for: conversation)
            } label: {
                Label(conversation.isPinned ? "Unpin" : "Pin", systemImage: "pin")
            }
            .tint(.orange)
            Button {
                chatStore.setMuted(!conversation.isMuted, for: conversation)
            } label: {
                Label(conversation.isMuted ? "Unmute" : "Mute", systemImage: conversation.isMuted ? "bell" : "bell.slash")
            }
            .tint(.blue)
        }
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    var isOnline: Bool = false
    var photoData: Data? = nil

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                if conversation.isGroup {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay(Image(systemName: "person.3.fill").foregroundStyle(.blue))
                } else {
                    AvatarView(photoData: photoData, initials: initials, tint: .green, size: 44)
                }
                if isOnline && !conversation.isGroup {
                    Circle().fill(Color.green).frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if conversation.isMuted {
                        Image(systemName: "bell.slash.fill").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(conversation.title).font(.body.weight(.medium))
                }
                Text(conversation.lastMessagePreview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let last = conversation.lastMessage {
                    Text(last.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if conversation.unreadCount > 0 {
                    Text("\(conversation.unreadCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var initials: String {
        let parts = conversation.title.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}
