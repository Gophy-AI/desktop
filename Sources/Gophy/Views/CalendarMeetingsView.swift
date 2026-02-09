import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct CalendarMeetingsView: View {
    enum SheetDestination: Identifiable {
        case meetingDetail(MeetingRecord)
        case newMeeting
        case newMeetingForEvent
        case linkDocument(MeetingRecord)

        var id: String {
            switch self {
            case .meetingDetail(let m): return "detail-\(m.id)"
            case .newMeeting: return "new"
            case .newMeetingForEvent: return "new-event"
            case .linkDocument(let m): return "link-\(m.id)"
            }
        }
    }

    @Environment(NavigationCoordinator.self) private var navigationCoordinator
    @State private var viewModel: CalendarMeetingsViewModel?
    @State private var initError: String?
    @State private var activeSheet: SheetDestination?
    @State private var playbackMeeting: MeetingRecord?
    @State private var selectedCalendarEvent: UnifiedCalendarEvent?
    @State private var isDroppingFile = false

    var body: some View {
        ZStack {
            Group {
                if let error = initError {
                    errorView(message: error)
                } else if let viewModel = viewModel {
                    calendarContent(viewModel: viewModel)
                } else {
                    SwiftUI.ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            if let meeting = playbackMeeting {
                PlaybackMeetingContainerView(
                    meeting: meeting,
                    fileURL: URL(fileURLWithPath: meeting.sourceFilePath ?? ""),
                    onDismiss: { playbackMeeting = nil }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: playbackMeeting?.id)
        .task {
            await initializeViewModel()
        }
    }

    private func openMeeting(_ meeting: MeetingRecord) {
        if meeting.mode == "playback", meeting.sourceFilePath != nil {
            playbackMeeting = meeting
        } else {
            activeSheet = .meetingDetail(meeting)
        }
    }

    // MARK: - Initialization

    private func initializeViewModel() async {
        do {
            let storage = StorageManager()
            let database = try GophyDatabase(storageManager: storage)
            let meetingRepo = MeetingRepository(database: database)
            let chatRepo = ChatMessageRepository(database: database)
            let documentRepo = DocumentRepository(database: database)
            let eventKit = EventKitService()

            var syncService: CalendarSyncService?
            let config = GoogleCalendarConfig()
            if config.isConfigured {
                let authService = GoogleAuthService(config: config)
                if await authService.isSignedIn {
                    let apiClient = GoogleCalendarAPIClient(authService: authService)
                    syncService = CalendarSyncService(
                        apiClient: apiClient,
                        eventKitService: eventKit
                    )
                }
            }

            let vm = CalendarMeetingsViewModel(
                meetingRepository: meetingRepo,
                chatMessageRepository: chatRepo,
                documentRepository: documentRepo,
                eventKitService: eventKit,
                calendarSyncService: syncService
            )
            viewModel = vm
            await vm.loadMeetings()
            await vm.loadCalendarEvents()
        } catch {
            initError = "Failed to initialize: \(error.localizedDescription)"
        }
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundStyle(.red)

            Text("Database Error")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Main Content

    private func calendarContent(viewModel: CalendarMeetingsViewModel) -> some View {
        VStack(spacing: 0) {
            headerBar(viewModel: viewModel)

            Divider()

            if !viewModel.searchQuery.isEmpty {
                searchResults(viewModel: viewModel)
            } else {
                switch viewModel.viewMode {
                case .month:
                    monthView(viewModel: viewModel)
                case .week:
                    weekView(viewModel: viewModel)
                case .day:
                    dayView(viewModel: viewModel)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
        .confirmationDialog(
            "Delete Meeting",
            isPresented: Bindable(viewModel).showDeleteConfirmation,
            presenting: viewModel.meetingToDelete
        ) { meeting in
            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteMeeting() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelDelete()
            }
        } message: { meeting in
            Text("Are you sure you want to delete '\(meeting.title)'? This action cannot be undone.")
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .meetingDetail(let meeting):
                MeetingDetailView(
                    viewModel: MeetingDetailViewModel(
                        meeting: meeting,
                        meetingRepository: viewModel.meetingRepository,
                        chatMessageRepository: viewModel.chatMessageRepository
                    )
                )
            case .newMeeting, .newMeetingForEvent:
                MeetingContainerView {
                    activeSheet = nil
                    selectedCalendarEvent = nil
                    Task { await viewModel.loadMeetings() }
                }
            case .linkDocument(let meeting):
                LinkDocumentSheet(
                    meetingId: meeting.id,
                    meetingTitle: meeting.title,
                    viewModel: viewModel
                )
            }
        }
        .fileImporter(
            isPresented: Bindable(viewModel).showImportRecording,
            allowedContentTypes: [.audio, .movie, .video, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        let securityScoped = url.startAccessingSecurityScopedResource()
                        defer { if securityScoped { url.stopAccessingSecurityScopedResource() } }
                        _ = await viewModel.importRecording(url: url)
                    }
                }
            case .failure(let error):
                viewModel.errorMessage = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Header

    private func headerBar(viewModel: CalendarMeetingsViewModel) -> some View {
        HStack(spacing: 12) {
            Text("Meetings")
                .font(.largeTitle)
                .fontWeight(.bold)

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search...", text: Bindable(viewModel).searchQuery)
                    .textFieldStyle(.plain)
                    .frame(width: 150)
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Picker("View", selection: Bindable(viewModel).viewMode) {
                ForEach(CalendarViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Menu {
                Button {
                    activeSheet = .newMeeting
                } label: {
                    Label("Start Meeting", systemImage: "play.fill")
                }
                Button {
                    viewModel.showImportRecording = true
                } label: {
                    Label("Import Recording", systemImage: "waveform.badge.plus")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.title3)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
        }
        .padding()
    }

    // MARK: - Month View

    private func monthView(viewModel: CalendarMeetingsViewModel) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                monthNavigation(viewModel: viewModel)
                monthGrid(viewModel: viewModel)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            dayDetailPanel(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func monthNavigation(viewModel: CalendarMeetingsViewModel) -> some View {
        HStack {
            Button { viewModel.navigateMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)

            Spacer()

            Button { viewModel.goToToday() } label: {
                Text(viewModel.monthYearString)
                    .font(.headline)
            }
            .buttonStyle(.plain)

            Spacer()

            Button { viewModel.navigateMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 12)
    }

    private func monthGrid(viewModel: CalendarMeetingsViewModel) -> some View {
        let days = viewModel.daysInMonthGrid()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        let weekdayLabels = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

        return VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(weekdayLabels, id: \.self) { label in
                    Text(label)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date = date {
                        dayCell(date: date, viewModel: viewModel)
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private func dayCell(date: Date, viewModel: CalendarMeetingsViewModel) -> some View {
        let isToday = viewModel.isToday(date)
        let isSelected = viewModel.isSelected(date)
        let eventCount = viewModel.eventCountForDate(date)

        return Button {
            viewModel.selectedDate = date
        } label: {
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(.body, design: .rounded))
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(isSelected ? .white : isToday ? Color.accentColor : .primary)

                if eventCount > 0 {
                    HStack(spacing: 2) {
                        ForEach(0..<min(eventCount, 3), id: \.self) { _ in
                            Circle()
                                .fill(isSelected ? Color.white.opacity(0.8) : Color.accentColor)
                                .frame(width: 4, height: 4)
                        }
                    }
                } else {
                    Spacer()
                        .frame(height: 4)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Week View

    private func weekView(viewModel: CalendarMeetingsViewModel) -> some View {
        VStack(spacing: 0) {
            weekNavigation(viewModel: viewModel)

            Divider()

            ScrollView {
                HStack(alignment: .top, spacing: 1) {
                    ForEach(viewModel.daysInWeek(), id: \.timeIntervalSince1970) { date in
                        weekDayColumn(date: date, viewModel: viewModel)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func weekNavigation(viewModel: CalendarMeetingsViewModel) -> some View {
        HStack {
            Button { viewModel.navigateWeek(by: -1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)

            Spacer()

            Button { viewModel.goToToday() } label: {
                Text(viewModel.weekRangeString)
                    .font(.headline)
            }
            .buttonStyle(.plain)

            Spacer()

            Button { viewModel.navigateWeek(by: 1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private func weekDayColumn(date: Date, viewModel: CalendarMeetingsViewModel) -> some View {
        let isToday = viewModel.isToday(date)
        let dayFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "EEE d"
            return f
        }()

        return VStack(spacing: 4) {
            Text(dayFormatter.string(from: date))
                .font(.caption)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(isToday ? Color.accentColor : .secondary)
                .frame(maxWidth: .infinity)

            Divider()

            let dayMeetings = viewModel.meetingsForDate(date)
            let dayEvents = viewModel.calendarEventsForDate(date)

            if dayMeetings.isEmpty && dayEvents.isEmpty {
                Text("No events")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(spacing: 4) {
                    ForEach(dayMeetings) { meeting in
                        weekEventCell(
                            title: meeting.title,
                            time: viewModel.formatTime(meeting.startedAt),
                            color: meeting.mode == "playback" ? .orange : .accentColor,
                            onTap: {
                                openMeeting(meeting)


                            }
                        )
                    }
                    ForEach(dayEvents) { event in
                        weekEventCell(
                            title: event.title,
                            time: viewModel.formatTime(event.startDate),
                            color: .green,
                            onTap: {
                                if let meeting = viewModel.meetingForCalendarEvent(event) {
                                    openMeeting(meeting)
    

                                } else {
                                    selectedCalendarEvent = event
                                    activeSheet = .newMeetingForEvent
                                }
                            }
                        )
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isToday ? Color.accentColor.opacity(0.05) : Color.clear)
        )
    }

    private func weekEventCell(title: String, time: String, color: Color, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Day View

    private func dayView(viewModel: CalendarMeetingsViewModel) -> some View {
        VStack(spacing: 0) {
            dayNavigation(viewModel: viewModel)

            Divider()

            dayDetailPanel(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dayNavigation(viewModel: CalendarMeetingsViewModel) -> some View {
        HStack {
            Button { viewModel.navigateDay(by: -1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)

            Spacer()

            Button { viewModel.goToToday() } label: {
                Text(viewModel.selectedDateString)
                    .font(.headline)
            }
            .buttonStyle(.plain)

            Spacer()

            Button { viewModel.navigateDay(by: 1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    // MARK: - Day Detail Panel (shared by month + day)

    private func dayDetailPanel(viewModel: CalendarMeetingsViewModel) -> some View {
        let dayMeetings = viewModel.meetingsForDate(viewModel.selectedDate)
        let dayEvents = viewModel.calendarEventsForDate(viewModel.selectedDate)

        return VStack(spacing: 0) {
            HStack {
                Text(viewModel.selectedDateString)
                    .font(.headline)
                Spacer()
                Text("\(dayMeetings.count + dayEvents.count) events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            if dayMeetings.isEmpty && dayEvents.isEmpty {
                recordingDropZone(viewModel: viewModel)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(dayMeetings) { meeting in
                            meetingRow(meeting: meeting, viewModel: viewModel)
                            Divider().padding(.leading, 16)
                        }
                        ForEach(dayEvents) { event in
                            calendarEventRow(event: event, viewModel: viewModel)
                            Divider().padding(.leading, 16)
                        }

                        recordingDropZone(viewModel: viewModel)
                            .frame(height: 80)
                            .padding()
                    }
                }
            }
        }
    }

    private func recordingDropZone(viewModel: CalendarMeetingsViewModel) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: isDroppingFile ? "arrow.down.circle.fill" : "waveform.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(isDroppingFile ? Color.accentColor : Color.secondary.opacity(0.3))
            Text(isDroppingFile ? "Drop to import" : "Drop audio or video file to add recording")
                .font(.subheadline)
                .foregroundStyle(isDroppingFile ? Color.accentColor : .secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isDroppingFile ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: isDroppingFile ? 2 : 1, dash: [6])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isDroppingFile) { providers in
            handleRecordingDrop(providers: providers, viewModel: viewModel)
        }
    }

    private func handleRecordingDrop(providers: [NSItemProvider], viewModel: CalendarMeetingsViewModel) -> Bool {
        guard let provider = providers.first else { return false }

        let supportedExtensions = Set(AudioFileImporter.supportedFormats)

        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            let url: URL?
            if let fileURL = item as? URL {
                url = fileURL
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = nil
            }

            guard let url, supportedExtensions.contains(url.pathExtension.lowercased()) else { return }

            Task { @MainActor in
                let securityScoped = url.startAccessingSecurityScopedResource()
                defer { if securityScoped { url.stopAccessingSecurityScopedResource() } }
                _ = await viewModel.importRecording(url: url)
            }
        }
        return true
    }

    // MARK: - Row Views

    private func meetingRow(
        meeting: MeetingRecord,
        viewModel: CalendarMeetingsViewModel
    ) -> some View {
        Button {
            openMeeting(meeting)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(viewModel.formatTime(meeting.startedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 55, alignment: .leading)

                        Text(meeting.title)
                            .font(.body)
                            .fontWeight(.medium)
                            .lineLimit(1)

                        modeBadge(mode: meeting.mode)
                        statusBadge(status: meeting.status)
                    }

                    HStack(spacing: 8) {
                        Spacer().frame(width: 55)

                        Label(viewModel.formatDuration(meeting), systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if meeting.mode == "playback", let count = meeting.speakerCount {
                            Label("\(count) speakers", systemImage: "person.2")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        activeSheet = .linkDocument(meeting)
                    } label: {
                        Image(systemName: "doc.badge.plus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Link Document")

                    Button {
                        Task { await navigationCoordinator.openChat(contextType: .meeting, contextId: meeting.id, title: meeting.title) }
                    } label: {
                        Image(systemName: "bubble.left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open Chat")

                    Button {
                        viewModel.confirmDelete(meeting)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                Task { await navigationCoordinator.openChat(contextType: .meeting, contextId: meeting.id, title: meeting.title) }
            } label: {
                Label("Open Chat", systemImage: "bubble.left")
            }
            Button {
                activeSheet = .linkDocument(meeting)
            } label: {
                Label("Link Document", systemImage: "doc.badge.plus")
            }
            Divider()
            Button(role: .destructive) {
                viewModel.confirmDelete(meeting)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func calendarEventRow(
        event: UnifiedCalendarEvent,
        viewModel: CalendarMeetingsViewModel
    ) -> some View {
        Button {
            if let meeting = viewModel.meetingForCalendarEvent(event) {
                openMeeting(meeting)
            } else {
                selectedCalendarEvent = event
                activeSheet = .newMeetingForEvent
            }
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text(event.isAllDay ? "All day" : viewModel.formatTime(event.startDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 55, alignment: .leading)

                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundStyle(.green)

                    Text(event.title)
                        .font(.body)
                        .lineLimit(1)

                    if event.source == .google {
                        Text("Google")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                Spacer()

                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Badges

    private func modeBadge(mode: String) -> some View {
        Group {
            switch mode {
            case "playback":
                Text("Recording")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .foregroundStyle(.orange)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            case "live":
                Text("Live")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .foregroundStyle(.green)
                    .background(Color.green.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            default:
                EmptyView()
            }
        }
    }

    private func statusBadge(status: String) -> some View {
        Group {
            if status != "completed" {
                Text(status.capitalized)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .foregroundStyle(.orange)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
    }

    // MARK: - Search Results

    private func searchResults(viewModel: CalendarMeetingsViewModel) -> some View {
        let matchedMeetings = viewModel.filteredMeetings
        let matchedEvents = viewModel.filteredCalendarEvents

        return Group {
            if matchedMeetings.isEmpty && matchedEvents.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("No results for \"\(viewModel.searchQuery)\"")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if !matchedMeetings.isEmpty {
                            Section {
                                ForEach(matchedMeetings) { meeting in
                                    meetingRow(meeting: meeting, viewModel: viewModel)
                                    Divider().padding(.leading, 16)
                                }
                            } header: {
                                sectionHeader("Meetings (\(matchedMeetings.count))")
                            }
                        }
                        if !matchedEvents.isEmpty {
                            Section {
                                ForEach(matchedEvents) { event in
                                    calendarEventRow(event: event, viewModel: viewModel)
                                    Divider().padding(.leading, 16)
                                }
                            } header: {
                                sectionHeader("Calendar Events (\(matchedEvents.count))")
                            }
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Link Document Sheet

@MainActor
struct LinkDocumentSheet: View {
    let meetingId: String
    let meetingTitle: String
    let viewModel: CalendarMeetingsViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var allDocuments: [DocumentRecord] = []
    @State private var linkedDocumentIds: Set<String> = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Link Documents")
                        .font(.headline)
                    Text(meetingTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            if isLoading {
                SwiftUI.ProgressView("Loading documents...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if allDocuments.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("No documents available")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Add documents in the Documents tab first")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(allDocuments) { document in
                        let isLinked = linkedDocumentIds.contains(document.id)
                        HStack(spacing: 12) {
                            Image(systemName: isLinked ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isLinked ? Color.accentColor : .secondary)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(document.name)
                                    .font(.body)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(document.type.uppercased())
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.secondary.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                    if document.pageCount > 0 {
                                        Text("\(document.pageCount) pages")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            Spacer()

                            if isLinked {
                                Button("Unlink") {
                                    Task {
                                        await viewModel.unlinkDocument(documentId: document.id)
                                        linkedDocumentIds.remove(document.id)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else {
                                Button("Link") {
                                    Task {
                                        await viewModel.linkDocument(documentId: document.id, to: meetingId)
                                        linkedDocumentIds.insert(document.id)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 480, height: 400)
        .task {
            let docs = await viewModel.allDocuments()
            let linked = await viewModel.linkedDocuments(for: meetingId)
            allDocuments = docs
            linkedDocumentIds = Set(linked.map(\.id))
            isLoading = false
        }
    }
}
