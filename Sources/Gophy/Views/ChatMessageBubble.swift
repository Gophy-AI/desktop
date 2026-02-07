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
                if message.role == "assistant" {
                    assistantBubble
                } else {
                    Text(renderMarkdown(message.content))
                        .textSelection(.enabled)
                        .padding(12)
                        .background(backgroundColor)
                        .foregroundStyle(foregroundColor)
                        .cornerRadius(12)
                }

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

    private var assistantBubble: some View {
        let parsed = Self.parseThinking(message.content)
        let showThinking = UserDefaults.standard.object(forKey: "inference.thinkingEnabled") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "inference.thinkingEnabled")

        return VStack(alignment: .leading, spacing: 0) {
            if showThinking, let thinking = parsed.thinking, !thinking.isEmpty {
                ThinkingDisclosure(thinking: thinking)
                    .padding(12)

                Divider()
                    .padding(.horizontal, 8)
            }

            if !parsed.response.isEmpty {
                Text(renderMarkdown(parsed.response))
                    .textSelection(.enabled)
                    .padding(12)
            } else if parsed.thinking != nil {
                Text("Thinking...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
        .background(backgroundColor)
        .foregroundStyle(foregroundColor)
        .cornerRadius(12)
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

    /// Parse `<think>...</think>` blocks from model output.
    /// Returns the thinking content (if any) and the actual response.
    static func parseThinking(_ text: String) -> (thinking: String?, response: String) {
        // Complete thinking block: <think>...</think>
        if let thinkStart = text.range(of: "<think>"),
           let thinkEnd = text.range(of: "</think>") {
            let thinking = String(text[thinkStart.upperBound..<thinkEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let response = String(text[thinkEnd.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (thinking, response)
        }

        // Incomplete thinking block (still streaming): <think>... (no closing tag)
        if let thinkStart = text.range(of: "<think>") {
            let thinking = String(text[thinkStart.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (thinking, "")
        }

        // No thinking block
        return (nil, text)
    }
}

@MainActor
private struct ThinkingDisclosure: View {
    let thinking: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Image(systemName: "brain")
                        .font(.caption)

                    Text("Thinking")
                        .font(.caption)
                        .fontWeight(.medium)

                    Spacer()
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(thinking)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
            }
        }
    }
}
