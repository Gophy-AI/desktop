import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "PlaybackMeetingView")

@MainActor
struct PlaybackMeetingView: View {
    @State private var viewModel: PlaybackMeetingViewModel
    @State private var shouldAutoScroll = true
    @State private var editingSpeaker: SpeakerIdentifier?
    @State private var editingSpeakerName: String = ""
    let onDismiss: () -> Void

    init(viewModel: PlaybackMeetingViewModel, onDismiss: @escaping () -> Void) {
        self._viewModel = State(initialValue: viewModel)
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            Divider()

            RecordingPlayerView(
                isPlaying: $viewModel.isPlaying,
                currentTime: $viewModel.currentTime,
                duration: $viewModel.duration,
                speed: $viewModel.speed,
                speakerCount: viewModel.speakerCount,
                onSeek: { time in
                    Task { await viewModel.seek(to: time) }
                },
                onTogglePlayback: {
                    Task { await viewModel.togglePlayback() }
                },
                onStop: {
                    Task { await viewModel.stopPlayback() }
                },
                onSpeedChange: { rate in
                    Task { await viewModel.setSpeed(rate) }
                },
                audioURL: viewModel.fileURL
            )

            Divider()

            HStack(spacing: 0) {
                transcriptArea

                Divider()

                SuggestionPanelView(
                    suggestions: viewModel.suggestions,
                    isGenerating: viewModel.isGeneratingSuggestion,
                    onRefresh: {
                        await viewModel.refreshSuggestions()
                    }
                )
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    Task {
                        if viewModel.isPlaying {
                            await viewModel.stopPlayback()
                        }
                        onDismiss()
                    }
                }
            }
        }
        .task {
            await viewModel.loadExistingData()
            if viewModel.status == .idle {
                await viewModel.startPlayback()
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        .sheet(item: $editingSpeaker) { speakerId in
            speakerRenameSheet(speaker: speakerId.value)
        }
    }

    // MARK: - Subviews

    private var topBar: some View {
        HStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.title3)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(viewModel.fileURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if viewModel.isTranscribingAll {
                HStack(spacing: 8) {
                    SwiftUI.ProgressView(value: viewModel.transcribeAllProgress)
                        .frame(width: 100)
                    Text("\(Int(viewModel.transcribeAllProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else {
                Button {
                    Task { await viewModel.transcribeAll() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "text.badge.checkmark")
                        Text("Transcribe All")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.status == .active)
                .help("Transcribe the entire recording without playback")
            }

            statusBadge
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch viewModel.status {
        case .idle, .completed:
            return .gray
        case .starting, .stopping:
            return .yellow
        case .active:
            return .green
        case .paused:
            return .orange
        }
    }

    private var statusText: String {
        switch viewModel.status {
        case .idle:
            return "Ready"
        case .starting:
            return "Loading..."
        case .active:
            return "Playing"
        case .paused:
            return "Paused"
        case .stopping:
            return "Stopping..."
        case .completed:
            return "Completed"
        }
    }

    private var transcriptArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if viewModel.transcriptSegments.isEmpty {
                        emptyTranscript
                    } else {
                        ForEach(Array(viewModel.transcriptSegments.enumerated()), id: \.element.id) { index, segment in
                            VStack(spacing: 0) {
                                PlaybackTranscriptRowView(
                                    segment: segment,
                                    speakerLabel: viewModel.displayLabel(for: segment.speaker),
                                    speakerColor: viewModel.speakerColor(for: segment.speaker),
                                    isActive: isSegmentActive(segment),
                                    onTap: {
                                        Task { await viewModel.seekToSegment(segment) }
                                    },
                                    onRenameSpeaker: {
                                        editingSpeakerName = viewModel.displayLabel(for: segment.speaker)
                                        editingSpeaker = SpeakerIdentifier(value: segment.speaker)
                                    }
                                )
                                .id(segment.id)

                                if index < viewModel.transcriptSegments.count - 1 {
                                    Divider()
                                        .padding(.leading, 12)
                                }
                            }
                        }
                    }
                }
            }
            .onChange(of: viewModel.transcriptSegments.count) { _, _ in
                if shouldAutoScroll, let lastSegment = viewModel.transcriptSegments.last {
                    withAnimation {
                        proxy.scrollTo(lastSegment.id, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var emptyTranscript: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No transcript yet")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Start playback to begin transcription")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    private func isSegmentActive(_ segment: TranscriptSegmentRecord) -> Bool {
        viewModel.currentTime >= segment.startTime && viewModel.currentTime < segment.endTime
    }

    private func speakerRenameSheet(speaker: String) -> some View {
        VStack(spacing: 16) {
            Text("Rename Speaker")
                .font(.headline)

            Text("Current: \(speaker)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("New name", text: $editingSpeakerName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)

            HStack {
                Button("Cancel") {
                    editingSpeaker = nil
                }
                .keyboardShortcut(.cancelAction)

                Button("Rename") {
                    if !editingSpeakerName.isEmpty {
                        Task {
                            await viewModel.renameSpeaker(
                                original: speaker,
                                newName: editingSpeakerName
                            )
                        }
                    }
                    editingSpeaker = nil
                }
                .keyboardShortcut(.defaultAction)
                .disabled(editingSpeakerName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}

// MARK: - SpeakerIdentifier for sheet binding

struct SpeakerIdentifier: Identifiable {
    let value: String
    var id: String { value }
}

// MARK: - PlaybackTranscriptRowView

@MainActor
struct PlaybackTranscriptRowView: View {
    let segment: TranscriptSegmentRecord
    let speakerLabel: String
    let speakerColor: Color
    let isActive: Bool
    let onTap: () -> Void
    let onRenameSpeaker: () -> Void

    private var formattedTime: String {
        let totalSeconds = Int(segment.startTime)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Button(action: onRenameSpeaker) {
                            Text(speakerLabel)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(speakerColor)
                        }
                        .buttonStyle(.plain)

                        Text(formattedTime)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(segment.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .foregroundStyle(.primary)
                }

                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    struct PreviewWrapper: View {
        var body: some View {
            Text("Preview not available")
        }
    }
    return PreviewWrapper()
}
