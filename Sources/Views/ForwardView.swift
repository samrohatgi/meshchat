import SwiftUI

/// Pick a conversation to forward a message to. The message text is
/// re-sent as a brand-new outgoing message in the target chat (with a
/// "Forwarded" label) - there's no attachment/media to carry along since
/// this app is text-only.
struct ForwardView: View {
    let message: ChatMessage
    var onForward: (Conversation) -> Void

    @EnvironmentObject var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var forwardedTo: Conversation?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Forwarded message", systemImage: "arrowshape.turn.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(message.displayText)
                            .font(.subheadline)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 2)
                }

                Section("Send to") {
                    if chatStore.conversations.isEmpty {
                        Text("No conversations yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(chatStore.conversations) { conversation in
                            Button {
                                forwardedTo = conversation
                                onForward(conversation)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: conversation.isGroup ? "person.3.fill" : "person.crop.circle.fill")
                                        .foregroundStyle(conversation.isGroup ? .blue : .green)
                                    Text(conversation.title)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Forward message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
