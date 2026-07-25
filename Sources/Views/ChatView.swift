import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private let quickReactions = ["👍", "❤️", "😂", "😮", "😢", "🙏"]

struct ChatView: View {
    let conversationID: UUID

    @EnvironmentObject var mesh: MeshManager
    @EnvironmentObject var chatStore: ChatStore
    @State private var draft: String = ""
    @State private var replyingTo: ChatMessage?
    @State private var editingMessage: ChatMessage?
    @State private var forwardingMessage: ChatMessage?
    @State private var showingSearch = false
    @State private var searchQuery = ""
    @State private var showingGroupInfo = false
    @State private var showingContactInfo = false
    @State private var isTypingLocally = false

    private var conversation: Conversation {
        if let existing = chatStore.conversations.first(where: { $0.id == conversationID }) { return existing }
        if let peer = mesh.connectedPeers.first(where: { $0.id == conversationID }) {
            return chatStore.conversation(for: peer)
        }
        return Conversation(id: conversationID, title: chatStore.displayName(for: conversationID), messages: [], isGroup: false, memberIDs: [conversationID])
    }

    private var messages: [ChatMessage] {
        guard showingSearch, !searchQuery.isEmpty else { return conversation.messages }
        return conversation.messages.filter { $0.text.localizedCaseInsensitiveContains(searchQuery) }
    }

    private var isDirectlyConnected: Bool {
        mesh.connectedPeers.contains(where: { $0.id == conversationID })
    }

    private var isPeerTyping: Bool {
        !conversation.isGroup && mesh.typingPeerIDs.contains(conversation.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showingSearch {
                TextField("Search in this chat", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .padding(8)
                    .background(.bar)
            }

            connectionBanner

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }
                        if isPeerTyping {
                            typingIndicator
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in scrollToBottom(proxy) }
                .onAppear { scrollToBottom(proxy) }
            }

            if let replyingTo {
                composerAccessory(
                    icon: "arrowshape.turn.up.left",
                    label: "Replying to \(replyingTo.senderName)",
                    detail: replyingTo.displayText
                ) { self.replyingTo = nil }
            }
            if let editingMessage {
                composerAccessory(icon: "pencil", label: "Editing message", detail: editingMessage.text) {
                    self.editingMessage = nil
                    draft = ""
                }
            }

            inputBar
        }
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { showingSearch.toggle(); if !showingSearch { searchQuery = "" } } label: {
                        Label(showingSearch ? "Hide search" : "Search in chat", systemImage: "magnifyingglass")
                    }
                    if conversation.isGroup {
                        Button { showingGroupInfo = true } label: { Label("Group info", systemImage: "info.circle") }
                    } else {
                        Button { showingContactInfo = true } label: { Label("Contact info", systemImage: "person.circle") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingGroupInfo) { GroupInfoView(conversationID: conversationID) }
        .sheet(isPresented: $showingContactInfo) { ContactInfoView(peerID: conversationID) }
        .sheet(item: $forwardingMessage) { message in
            ForwardView(message: message) { target in
                chatStore.forward(message, to: target)
            }
        }
        .onAppear { chatStore.markAsRead(conversation) }
        .onChange(of: messages.count) { _ in chatStore.markAsRead(conversation) }
    }

    // MARK: Rows

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        MessageBubble(message: message, showSenderName: conversation.isGroup)
            .contextMenu {
                Button { replyingTo = message } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
                Menu {
                    ForEach(quickReactions, id: \.self) { emoji in
                        Button(emoji) { chatStore.react(emoji, to: message, in: conversation) }
                    }
                    if message.reactions[mesh.myID.uuidString] != nil {
                        Button("Remove reaction", role: .destructive) { chatStore.react(nil, to: message, in: conversation) }
                    }
                } label: {
                    Label("React", systemImage: "face.smiling")
                }
                Button { UIPasteboard.general.string = message.displayText } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                Button { chatStore.toggleStar(message, in: conversation) } label: {
                    Label(message.isStarred ? "Unstar" : "Star", systemImage: message.isStarred ? "star.slash" : "star")
                }
                Button { forwardingMessage = message } label: { Label("Forward", systemImage: "arrowshape.turn.up.right") }
                if message.isOutgoing && !message.isDeletedForEveryone {
                    Button {
                        editingMessage = message
                        draft = message.text
                    } label: { Label("Edit", systemImage: "pencil") }
                }
                if !message.isDeletedForEveryone {
                    Button(role: .destructive) { chatStore.deleteForMe(message, in: conversation) } label: {
                        Label("Delete for me", systemImage: "trash")
                    }
                    if message.isOutgoing {
                        Button(role: .destructive) { chatStore.deleteForEveryone(message, in: conversation) } label: {
                            Label("Delete for everyone", systemImage: "trash.fill")
                        }
                    }
                }
            }
    }

    private var typingIndicator: some View {
        HStack {
            Text("\(conversation.title) is typing…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var connectionBanner: some View {
        HStack(spacing: 6) {
            if !conversation.isGroup {
                Circle()
                    .fill(isDirectlyConnected ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(isDirectlyConnected
                     ? "Connected directly"
                     : "Out of direct range - messages will relay through the mesh if possible")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "person.3.fill").font(.caption2).foregroundStyle(.secondary)
                Text("\(conversation.memberIDs.count) members")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
    }

    private func composerAccessory(icon: String, label: String, detail: String, onCancel: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption.weight(.medium))
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { onCancel() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
        }
        .padding(8)
        .background(.thinMaterial)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .onChange(of: draft) { newValue in
                    let typing = !newValue.trimmingCharacters(in: .whitespaces).isEmpty
                    if typing != isTypingLocally {
                        isTypingLocally = typing
                        chatStore.setTyping(typing, in: conversation)
                    }
                }

            Button {
                send()
            } label: {
                Image(systemName: editingMessage != nil ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(draft.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .green)
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(8)
        .background(.bar)
    }

    private func send() {
        if let editingMessage {
            chatStore.editMyMessage(editingMessage, newText: draft, in: conversation)
            self.editingMessage = nil
        } else {
            chatStore.sendMessage(draft, to: conversation, replyTo: replyingTo)
            replyingTo = nil
        }
        if isTypingLocally {
            isTypingLocally = false
            chatStore.setTyping(false, in: conversation)
        }
        draft = ""
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = messages.last else { return }
        withAnimation {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}
