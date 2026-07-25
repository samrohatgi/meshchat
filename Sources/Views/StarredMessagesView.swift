import SwiftUI

struct StarredMessagesView: View {
    @EnvironmentObject var chatStore: ChatStore

    var body: some View {
        List {
            if chatStore.starredMessages.isEmpty {
                Text("No starred messages. Long-press any message and tap Star to save it here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(chatStore.starredMessages, id: \.message.id) { entry in
                    NavigationLink {
                        ChatView(conversationID: entry.conversation.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.conversation.title).font(.subheadline.weight(.medium))
                                Spacer()
                                Text(entry.message.timestamp, style: .date)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(entry.message.senderName): \(entry.message.displayText)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Starred messages")
    }
}
