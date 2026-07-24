import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isOutgoing { Spacer(minLength: 40) }

            VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 3) {
                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.isOutgoing ? Color.green : Color(.systemGray5))
                    .foregroundStyle(message.isOutgoing ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                HStack(spacing: 4) {
                    Text(message.timestamp, style: .time)
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

    @ViewBuilder
    private var statusIcon: some View {
        switch message.deliveryState {
        case .sending:
            Image(systemName: "clock")
        case .sentDirect, .relayed:
            Image(systemName: "checkmark")
        case .failed:
            Image(systemName: "exclamationmark.triangle")
        }
    }
}
