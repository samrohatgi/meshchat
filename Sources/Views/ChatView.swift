import SwiftUI

struct ChatView: View {
    let peerID: UUID
    let peerName: String

    @EnvironmentObject var mesh: MeshManager
    @EnvironmentObject var chatStore: ChatStore
    @State private var draft: String = ""

    private var messages: [ChatMessage] {
        chatStore.conversations.first(where: { $0.peerID == peerID })?.messages ?? []
    }

    private var isDirectlyConnected: Bool {
        mesh.connectedPeers.contains(where: { $0.id == peerID })
    }

    var body: some View {
        VStack(spacing: 0) {
            connectionBanner

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    scrollToBottom(proxy)
                }
                .onAppear {
                    scrollToBottom(proxy)
                }
            }

            inputBar
        }
        .navigationTitle(peerName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var connectionBanner: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isDirectlyConnected ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(isDirectlyConnected
                 ? "Connected directly"
                 : "Out of direct range - messages will relay through the mesh if possible")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)

            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(draft.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .green)
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(8)
        .background(.bar)
    }

    private func send() {
        let peer = mesh.connectedPeers.first(where: { $0.id == peerID })
            ?? MeshPeer(id: peerID, displayName: peerName, mcPeerID: nil, isConnectedDirectly: false, lastSeen: Date())
        chatStore.sendMessage(draft, to: peer)
        draft = ""
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = messages.last else { return }
        withAnimation {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}
