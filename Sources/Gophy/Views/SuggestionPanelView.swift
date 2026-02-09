import SwiftUI

@MainActor
struct SuggestionPanelView: View {
    let suggestions: [ChatMessageRecord]
    let isGenerating: Bool
    let onRefresh: () async -> Void
    var ttsPlaybackService: TTSPlaybackService?

    @State private var expandedSuggestions: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI Suggestions")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: {
                    Task {
                        await onRefresh()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(isGenerating)
            }

            if isGenerating {
                HStack(spacing: 8) {
                    SwiftUI.ProgressView()
                        .controlSize(.small)

                    Text("Generating suggestion...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if suggestions.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "lightbulb")
                                .font(.title)
                                .foregroundStyle(.secondary)

                            Text("No suggestions yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text("Click Refresh to generate")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(suggestions.reversed(), id: \.id) { suggestion in
                            SuggestionItemView(
                                suggestion: suggestion,
                                isExpanded: expandedSuggestions.contains(suggestion.id),
                                onToggle: {
                                    toggleExpanded(suggestion.id)
                                },
                                ttsPlaybackService: ttsPlaybackService
                            )
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .frame(width: 300)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func toggleExpanded(_ id: String) {
        if expandedSuggestions.contains(id) {
            expandedSuggestions.remove(id)
        } else {
            expandedSuggestions.insert(id)
        }
    }
}

@MainActor
struct SuggestionItemView: View {
    let suggestion: ChatMessageRecord
    let isExpanded: Bool
    let onToggle: () -> Void
    var ttsPlaybackService: TTSPlaybackService?

    private var timeAgo: String {
        let interval = Date().timeIntervalSince(suggestion.createdAt)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        }
    }

    private var isPlayingThis: Bool {
        guard let service = ttsPlaybackService else { return false }
        return service.isPlaying && service.currentText == suggestion.content
    }

    private var isLoadingThis: Bool {
        guard let service = ttsPlaybackService else { return false }
        return service.isLoading && service.currentText == suggestion.content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)

                Text(timeAgo)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                if let service = ttsPlaybackService {
                    ttsButton(service: service)
                }

                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                Text(suggestion.content)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineLimit(nil)
            } else {
                Text(suggestion.content)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func ttsButton(service: TTSPlaybackService) -> some View {
        if isLoadingThis {
            SwiftUI.ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
        } else if isPlayingThis {
            Button(action: {
                service.stop()
            }) {
                Image(systemName: "stop.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Stop reading")
        } else {
            Button(action: {
                service.play(text: suggestion.content)
            }) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(service.isPlaying || service.isLoading)
            .help("Read aloud")
        }
    }
}

#Preview {
    SuggestionPanelView(
        suggestions: [
            ChatMessageRecord(
                id: "1",
                role: "assistant",
                content: "Consider asking about the project timeline to ensure alignment with the team's expectations.",
                meetingId: "meeting1",
                createdAt: Date().addingTimeInterval(-300)
            ),
            ChatMessageRecord(
                id: "2",
                role: "assistant",
                content: "Based on the discussion, it might be helpful to clarify the budget constraints before moving forward.",
                meetingId: "meeting1",
                createdAt: Date().addingTimeInterval(-60)
            )
        ],
        isGenerating: false,
        onRefresh: {}
    )
    .frame(height: 500)
}
