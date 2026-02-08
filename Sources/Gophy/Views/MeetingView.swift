import SwiftUI

@MainActor
struct MeetingView: View {
    @State private var viewModel: MeetingViewModel
    @State private var shouldAutoScroll = true
    @State private var scrollProxy: ScrollViewProxy?
    var ttsPlaybackService: TTSPlaybackService?

    init(viewModel: MeetingViewModel, ttsPlaybackService: TTSPlaybackService? = nil) {
        self._viewModel = State(initialValue: viewModel)
        self.ttsPlaybackService = ttsPlaybackService
    }

    private var formattedDuration: String {
        let duration = Int(viewModel.duration)
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var statusText: String {
        switch viewModel.status {
        case .idle:
            return "Ready"
        case .starting:
            return "Starting..."
        case .active:
            return "Recording"
        case .paused:
            return "Paused"
        case .stopping:
            return "Stopping..."
        case .completed:
            return "Completed"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                topBar

                Divider()

                transcriptArea

                MeetingControlBar(
                    status: viewModel.status,
                    micLevel: viewModel.micLevel,
                    systemAudioLevel: viewModel.systemAudioLevel,
                    onStart: {
                        await viewModel.startMeeting()
                    },
                    onStop: {
                        await viewModel.stopMeeting()
                    },
                    onPause: {
                        await viewModel.pauseMeeting()
                    },
                    onResume: {
                        await viewModel.resumeMeeting()
                    }
                )
            }

            Divider()

            SuggestionPanelView(
                suggestions: viewModel.suggestions,
                isGenerating: viewModel.isGeneratingSuggestion,
                onRefresh: {
                    await viewModel.refreshSuggestions()
                },
                ttsPlaybackService: ttsPlaybackService
            )
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
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            TextField("Meeting Title", text: $viewModel.title)
                .textFieldStyle(.plain)
                .font(.headline)
                .disabled(viewModel.status == .active || viewModel.status == .paused)

            Spacer()

            Picker("", selection: Binding(
                get: { viewModel.selectedLanguage },
                set: { newValue in
                    Task {
                        await viewModel.updateLanguage(newValue)
                    }
                }
            )) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)

            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(formattedDuration)
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusColor: Color {
        switch viewModel.status {
        case .idle, .completed:
            return .gray
        case .starting, .stopping:
            return .yellow
        case .active:
            return .red
        case .paused:
            return .orange
        }
    }

    private var transcriptArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if viewModel.transcriptSegments.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "waveform")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)

                            Text("No transcript yet")
                                .font(.title3)
                                .foregroundStyle(.secondary)

                            Text("Start the meeting to begin transcription")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 60)
                    } else {
                        ForEach(Array(viewModel.transcriptSegments.enumerated()), id: \.element.id) { index, segment in
                            VStack(spacing: 0) {
                                TranscriptRowView(
                                    segment: segment,
                                    meetingStartTime: Date()
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
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: geometry.frame(in: .named("scroll")).minY
                    )
                }
            )
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                handleScrollOffset(offset)
            }
            .onChange(of: viewModel.transcriptSegments.count) { oldValue, newValue in
                if shouldAutoScroll, let lastSegment = viewModel.transcriptSegments.last {
                    withAnimation {
                        proxy.scrollTo(lastSegment.id, anchor: .bottom)
                    }
                }
            }
            .onAppear {
                scrollProxy = proxy
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func handleScrollOffset(_ offset: CGFloat) {
        if offset < -50 {
            shouldAutoScroll = false
        } else if offset > -10 {
            shouldAutoScroll = true
        }
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
