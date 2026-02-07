import SwiftUI

@MainActor
struct UpcomingMeetingsView: View {
    @State private var viewModel: UpcomingMeetingsViewModel
    var onStartRecording: ((UnifiedCalendarEvent) -> Void)?

    init(
        viewModel: UpcomingMeetingsViewModel,
        onStartRecording: ((UnifiedCalendarEvent) -> Void)? = nil
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.onStartRecording = onStartRecording
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if viewModel.upcomingMeetings.isEmpty {
                emptyState
            } else {
                meetingList
            }
        }
        .onAppear {
            viewModel.startListening()
        }
        .onDisappear {
            viewModel.stopListening()
        }
    }

    private var header: some View {
        HStack {
            Text("Upcoming Meetings")
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            Button(action: {
                Task {
                    await viewModel.refresh()
                }
            }) {
                if viewModel.isRefreshing {
                    SwiftUI.ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline)
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isRefreshing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("No upcoming meetings")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var meetingList: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.upcomingMeetings) { event in
                MeetingRowView(
                    event: event,
                    proximity: viewModel.proximityColor(for: event),
                    formattedTime: viewModel.formattedTime(for: event),
                    formattedDuration: viewModel.formattedDuration(for: event),
                    showStartRecording: viewModel.shouldShowStartRecording(for: event),
                    onStartRecording: {
                        onStartRecording?(event)
                    },
                    onOpenLink: {
                        if let link = event.meetingLink, let url = URL(string: link) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )

                if event.id != viewModel.upcomingMeetings.last?.id {
                    Divider()
                        .padding(.leading, 12)
                }
            }
        }
    }
}

// MARK: - MeetingRowView

@MainActor
private struct MeetingRowView: View {
    let event: UnifiedCalendarEvent
    let proximity: MeetingProximity
    let formattedTime: String
    let formattedDuration: String
    let showStartRecording: Bool
    var onStartRecording: (() -> Void)?
    var onOpenLink: (() -> Void)?

    private var proximityColor: Color {
        switch proximity {
        case .now:
            return .red
        case .imminent:
            return .green
        case .soon:
            return .yellow
        case .later:
            return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(proximityColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(formattedTime)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    Text(formattedDuration)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(event.title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            if event.meetingLink != nil {
                Button(action: {
                    onOpenLink?()
                }) {
                    Image(systemName: "video.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("Open meeting link")
            }

            if showStartRecording {
                Button(action: {
                    onStartRecording?()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "record.circle")
                            .font(.caption)
                        Text("Record")
                            .font(.caption)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
