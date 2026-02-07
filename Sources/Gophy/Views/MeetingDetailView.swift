import SwiftUI

@MainActor
struct MeetingDetailView: View {
    @State private var viewModel: MeetingDetailViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: MeetingDetailViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            tabSelector

            Divider()

            if viewModel.isLoading {
                VStack {
                    Spacer()
                    SwiftUI.ProgressView()
                        .controlSize(.large)
                    Text("Loading meeting details...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    Spacer()
                }
            } else {
                content
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .task {
            await viewModel.loadData()
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(viewModel.meeting.title)
                    .font(.title)
                    .fontWeight(.bold)

                Spacer()

                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 20) {
                if viewModel.isImportedRecording {
                    DatePicker(
                        "Meeting Date",
                        selection: $viewModel.meetingDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .font(.subheadline)
                    .onChange(of: viewModel.meetingDate) { _, newDate in
                        Task { await viewModel.updateMeetingDate(newDate) }
                    }
                } else {
                    Label(viewModel.formatDate(), systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Label(viewModel.formatDuration(), systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Label("\(viewModel.segmentCount()) segments", systemImage: "text.bubble")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                if viewModel.meeting.calendarEventId != nil {
                    Button(action: {
                        Task {
                            await viewModel.writeSummaryToCalendar()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar.badge.checkmark")
                            Text(viewModel.isWritingBack ? "Writing..." : "Write Summary to Calendar")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isWritingBack || viewModel.transcriptSegments.isEmpty)
                }

                Button(action: {}) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var tabSelector: some View {
        Picker("View", selection: $viewModel.selectedTab) {
            ForEach(MeetingDetailViewModel.DetailTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var content: some View {
        Group {
            switch viewModel.selectedTab {
            case .transcript:
                transcriptTab
            case .suggestions:
                suggestionsTab
            }
        }
    }

    private var transcriptTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if viewModel.transcriptSegments.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)

                        Text("No transcript available")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    ForEach(Array(viewModel.transcriptSegments.enumerated()), id: \.element.id) { index, segment in
                        VStack(spacing: 0) {
                            TranscriptDetailRowView(segment: segment)

                            if index < viewModel.transcriptSegments.count - 1 {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var suggestionsTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if viewModel.suggestions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "lightbulb")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)

                        Text("No suggestions available")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    ForEach(viewModel.suggestions, id: \.id) { suggestion in
                        SuggestionDetailView(suggestion: suggestion)
                    }
                }
            }
            .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

@MainActor
struct TranscriptDetailRowView: View {
    let segment: TranscriptSegmentRecord

    private var formattedTime: String {
        let seconds = Int(segment.startTime)
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private var speakerColor: Color {
        if segment.speaker.lowercased() == "you" || segment.speaker.lowercased() == "user" {
            return .blue
        } else {
            return .green
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(segment.speaker)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(speakerColor)

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
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}

@MainActor
struct SuggestionDetailView: View {
    let suggestion: ChatMessageRecord

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: suggestion.createdAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.subheadline)
                    .foregroundStyle(.yellow)

                Text(formattedTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            Text(suggestion.content)
                .font(.body)
                .textSelection(.enabled)
                .foregroundStyle(.primary)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
