import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    var showSenderName: Bool = false
    var senderPhotoData: Data? = nil

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.isOutgoing { Spacer(minLength: 40) }

            if showSenderName && !message.isOutgoing {
                AvatarView(photoData: senderPhotoData, initials: senderInitials, tint: senderColor, size: 24)
            }

            VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 3) {
                if message.isDeletedForEveryone {
                    deletedBubble
                } else {
                    bubble
                }

                if !message.reactions.isEmpty && !message.isDeletedForEveryone {
                    reactionsRow
                }

                HStack(spacing: 4) {
                    Text(message.timestamp, style: .time)
                    if message.isEdited && !message.isDeletedForEveryone {
                        Text("edited")
                    }
                    if message.hopCount > 0 {
                        Image(systemName: "arrow.triangle.branch")
                        Text("relayed ×\(message.hopCount)")
                    }
                    if message.isOutgoing {
                        statusIcon
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if !message.isOutgoing { Spacer(minLength: 40) }
        }
    }

    // MARK: Bubble content

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showSenderName && !message.isOutgoing {
                Text(message.senderName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(senderColor)
            }

            if let replyPreviewText = message.replyPreviewText {
                replyPreview(sender: message.replyPreviewSender ?? "Unknown", text: replyPreviewText)
            }

            Text(formattedText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(message.isOutgoing ? Color.green : Color(.systemGray5))
        .foregroundStyle(message.isOutgoing ? .white : .primary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var deletedBubble: some View {
        HStack(spacing: 6) {
            Image(systemName: "slash.circle")
            Text("This message was deleted")
        }
        .italic()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(.secondary)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func replyPreview(sender: String, text: String) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(message.isOutgoing ? Color.white.opacity(0.6) : Color.green)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(sender)
                    .font(.caption2.weight(.semibold))
                Text(text)
                    .font(.caption2)
                    .lineLimit(2)
            }
        }
        .padding(6)
        .background((message.isOutgoing ? Color.white : Color.black).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var reactionsRow: some View {
        HStack(spacing: 2) {
            ForEach(reactionSummary, id: \.emoji) { entry in
                Text(entry.count > 1 ? "\(entry.emoji) \(entry.count)" : entry.emoji)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }
        }
    }

    private var reactionSummary: [(emoji: String, count: Int)] {
        var counts: [String: Int] = [:]
        for emoji in message.reactions.values { counts[emoji, default: 0] += 1 }
        return counts.map { (emoji: $0.key, count: $0.value) }.sorted { $0.emoji < $1.emoji }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch message.deliveryState {
        case .sending:
            Image(systemName: "clock")
        case .sentDirect, .relayed:
            Image(systemName: "checkmark")
        case .read:
            Image(systemName: "checkmark").foregroundStyle(.blue)
        case .failed:
            Image(systemName: "exclamationmark.triangle")
        }
    }

    private var senderColor: Color {
        let palette: [Color] = [.blue, .purple, .orange, .pink, .teal, .indigo]
        let hash = abs(message.senderID.uuidString.hashValue)
        return palette[hash % palette.count]
    }

    private var senderInitials: String {
        let parts = message.senderName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    // MARK: Lightweight text formatting: *bold*, _italic_, ~strike~

    private var formattedText: AttributedString {
        MessageTextFormatter.format(message.text)
    }
}

/// Parses a small WhatsApp-style subset of inline markup: *bold*, _italic_,
/// ~strikethrough~. No nesting, no escaping - deliberately simple since this
/// is plain-text chat, not a rich editor.
enum MessageTextFormatter {
    static func format(_ raw: String) -> AttributedString {
        var result = AttributedString()
        var buffer = ""
        var activeMarker: Character?

        func flushBuffer(styled: Bool) {
            guard !buffer.isEmpty else { return }
            var chunk = AttributedString(buffer)
            if styled, let marker = activeMarker {
                switch marker {
                case "*": chunk.font = .body.bold()
                case "_": chunk.font = .body.italic()
                case "~": chunk.strikethroughStyle = .single
                default: break
                }
            }
            result += chunk
            buffer = ""
        }

        let markers: Set<Character> = ["*", "_", "~"]
        var i = raw.startIndex
        while i < raw.endIndex {
            let ch = raw[i]
            if let marker = activeMarker {
                if ch == marker {
                    flushBuffer(styled: true)
                    activeMarker = nil
                } else {
                    buffer.append(ch)
                }
            } else if markers.contains(ch) {
                let closingExists: Bool = {
                    let rest = raw[raw.index(after: i)...]
                    return rest.contains(ch)
                }()
                if closingExists {
                    flushBuffer(styled: false)
                    activeMarker = ch
                } else {
                    buffer.append(ch)
                }
            } else {
                buffer.append(ch)
            }
            i = raw.index(after: i)
        }
        flushBuffer(styled: activeMarker != nil)
        return result
    }
}
