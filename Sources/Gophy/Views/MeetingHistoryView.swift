import SwiftUI

@MainActor
struct MeetingHistoryView: View {
    @State private var viewModel: MeetingHistoryViewModel
    @State private var selectedMeeting: MeetingRecord?
    @State private var showDetail = false
    @State private var showNewMeeting = false
    private let meetingRepository: MeetingRepository
    private let chatMessageRepository: ChatMessageRepository

    init(
        viewModel: MeetingHistoryViewModel,
        meetingRepository: MeetingRepository,
        chatMessageRepository: ChatMessageRepository
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.meetingRepository = meetingRepository
        self.chatMessageRepository = chatMessageRepository
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Meeting History")
                    .font(.title)
                    .fontWeight(.bold)

                Spacer()

                Button(action: {
                    showNewMeeting = true
                }) {
                    Label("Start Meeting", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search meetings...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        Task {
                            await viewModel.searchMeetings()
                        }
                    }

                if !viewModel.searchQuery.isEmpty {
                    Button(action: {
                        viewModel.searchQuery = ""
                        Task {
                            await viewModel.loadMeetings()
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)

            Divider()
                .padding(.top, 12)

            if viewModel.isLoading {
                VStack {
                    Spacer()
                    SwiftUI.ProgressView()
                        .controlSize(.large)
                    Text("Loading meetings...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    Spacer()
                }
            } else if viewModel.filteredMeetings.isEmpty {
                emptyState
            } else {
                meetingList
            }
        }
        .task {
            await viewModel.loadMeetings()
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
        .confirmationDialog(
            "Delete Meeting",
            isPresented: $viewModel.showDeleteConfirmation,
            presenting: viewModel.meetingToDelete
        ) { meeting in
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteMeeting()
                }
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelDelete()
            }
        } message: { meeting in
            Text("Are you sure you want to delete '\(meeting.title)'? This action cannot be undone.")
        }
        .sheet(isPresented: $showDetail) {
            if let meeting = selectedMeeting {
                MeetingDetailView(
                    viewModel: MeetingDetailViewModel(
                        meeting: meeting,
                        meetingRepository: meetingRepository,
                        chatMessageRepository: chatMessageRepository
                    )
                )
            }
        }
        .sheet(isPresented: $showNewMeeting) {
            MeetingContainerView {
                showNewMeeting = false
                Task {
                    await viewModel.loadMeetings()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("No meetings yet")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            Text("Start a meeting to begin recording and transcribing")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(action: {
                showNewMeeting = true
            }) {
                Label("Start Meeting", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var meetingList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.filteredMeetings.enumerated()), id: \.element.id) { index, meeting in
                    MeetingListRowView(
                        meeting: meeting,
                        onSelect: {
                            selectedMeeting = meeting
                            showDetail = true
                        },
                        onDelete: {
                            viewModel.confirmDelete(meeting)
                        },
                        formatDuration: { viewModel.formatDuration(meeting) },
                        formatDate: { viewModel.formatDate(meeting.startedAt) }
                    )

                    if index < viewModel.filteredMeetings.count - 1 {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
        }
    }
}

@MainActor
struct MeetingListRowView: View {
    let meeting: MeetingRecord
    let onSelect: () -> Void
    let onDelete: () -> Void
    let formatDuration: () -> String
    let formatDate: () -> String

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(meeting.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if meeting.mode == "playback" {
                            Image(systemName: "waveform")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                        }
                    }

                    HStack(spacing: 12) {
                        Label(formatDate(), systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Label(formatDuration(), systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if meeting.mode == "playback", let count = meeting.speakerCount {
                            Label("\(count) speakers", systemImage: "person.2")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if meeting.status != "completed" {
                            Label(meeting.status.capitalized, systemImage: "circle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
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
