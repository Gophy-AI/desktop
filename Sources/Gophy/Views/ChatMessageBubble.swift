import SwiftUI
import AppKit

@MainActor
struct ChatMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer(minLength: 80)
            }

            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 4) {
                Text(renderMarkdown(message.content))
                    .textSelection(.enabled)
                    .padding(12)
                    .background(backgroundColor)
                    .foregroundStyle(foregroundColor)
                    .cornerRadius(12)

                Text(formatTime(message.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            if message.role == "assistant" {
                Spacer(minLength: 80)
            }
        }
    }

    private var backgroundColor: Color {
        message.role == "user" ? .blue : Color(nsColor: .controlBackgroundColor)
    }

    private var foregroundColor: Color {
        message.role == "user" ? .white : .primary
    }

    private func renderMarkdown(_ text: String) -> AttributedString {
        do {
            return try AttributedString(markdown: text)
        } catch {
            return AttributedString(text)
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
