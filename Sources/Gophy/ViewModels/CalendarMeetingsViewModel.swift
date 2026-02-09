import Foundation
import SwiftUI

enum CalendarViewMode: String, CaseIterable, Sendable {
    case month = "Month"
    case week = "Week"
    case day = "Day"
}

@MainActor
@Observable
public final class CalendarMeetingsViewModel {
    // MARK: - State

    var selectedDate: Date = Date()
    var viewMode: CalendarViewMode = .month
    var meetings: [MeetingRecord] = []
    var calendarEvents: [UnifiedCalendarEvent] = []
    var searchQuery: String = ""
    var isLoading = false
    var errorMessage: String?
    var showDeleteConfirmation = false
    var meetingToDelete: MeetingRecord?
    var showNewMeeting = false
    var showImportRecording = false

    // MARK: - Dependencies

    let meetingRepository: MeetingRepository
    let chatMessageRepository: ChatMessageRepository
    let documentRepository: DocumentRepository
    private let eventKitService: EventKitService?
    private let calendarSyncService: (any CalendarSyncServiceProtocol)?

    private let calendar = Calendar.current
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    // MARK: - Init

    init(
        meetingRepository: MeetingRepository,
        chatMessageRepository: ChatMessageRepository,
        documentRepository: DocumentRepository,
        eventKitService: EventKitService? = nil,
        calendarSyncService: (any CalendarSyncServiceProtocol)? = nil
    ) {
        self.meetingRepository = meetingRepository
        self.chatMessageRepository = chatMessageRepository
        self.documentRepository = documentRepository
        self.eventKitService = eventKitService
        self.calendarSyncService = calendarSyncService
    }

    // MARK: - Data Loading

    func loadMeetings() async {
        isLoading = true
        defer { isLoading = false }

        do {
            meetings = try await meetingRepository.listAll()
        } catch {
            errorMessage = "Failed to load meetings: \(error.localizedDescription)"
        }
    }

    func loadCalendarEvents() async {
        if let syncService = calendarSyncService {
            do {
                calendarEvents = try await syncService.syncNow()
                return
            } catch {
                // Fall through to EventKit-only
            }
        }

        guard let service = eventKitService else { return }

        do {
            let granted = try await service.requestAccess()
            guard granted else { return }
        } catch {
            return
        }

        let range = visibleDateRange()
        let localEvents = service.fetchUpcomingEvents(
            from: range.start,
            to: range.end,
            calendars: nil
        )

        calendarEvents = localEvents.map { event in
            UnifiedCalendarEvent(
                id: "eventkit-\(event.identifier)",
                title: event.title,
                startDate: event.startDate,
                endDate: event.endDate,
                location: event.location,
                isAllDay: event.isAllDay,
                meetingLink: event.url?.absoluteString,
                attendees: [],
                source: .eventKit,
                googleEventId: nil,
                calendarId: nil
            )
        }
    }

    // MARK: - Filtering

    func meetingsForDate(_ date: Date) -> [MeetingRecord] {
        meetings.filter { calendar.isDate($0.startedAt, inSameDayAs: date) }
            .sorted { $0.startedAt < $1.startedAt }
    }

    func calendarEventsForDate(_ date: Date) -> [UnifiedCalendarEvent] {
        calendarEvents.filter { calendar.isDate($0.startDate, inSameDayAs: date) }
            .sorted { $0.startDate < $1.startDate }
    }

    func datesWithEvents(in month: Date) -> Set<DateComponents> {
        var result = Set<DateComponents>()

        guard let range = calendar.range(of: .day, in: .month, for: month),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) else {
            return result
        }

        for day in range {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) else { continue }
            let hasMeeting = meetings.contains { calendar.isDate($0.startedAt, inSameDayAs: date) }
            let hasEvent = calendarEvents.contains { calendar.isDate($0.startDate, inSameDayAs: date) }
            if hasMeeting || hasEvent {
                result.insert(calendar.dateComponents([.year, .month, .day], from: date))
            }
        }

        return result
    }

    var filteredMeetings: [MeetingRecord] {
        guard !searchQuery.isEmpty else { return [] }
        return meetings.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var filteredCalendarEvents: [UnifiedCalendarEvent] {
        guard !searchQuery.isEmpty else { return [] }
        return calendarEvents.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) }
            .sorted { $0.startDate > $1.startDate }
    }

    // MARK: - Delete

    func confirmDelete(_ meeting: MeetingRecord) {
        meetingToDelete = meeting
        showDeleteConfirmation = true
    }

    func deleteMeeting() async {
        guard let meeting = meetingToDelete else { return }

        do {
            try await meetingRepository.delete(id: meeting.id)
            meetings.removeAll { $0.id == meeting.id }
            meetingToDelete = nil
            showDeleteConfirmation = false
        } catch {
            errorMessage = "Failed to delete meeting: \(error.localizedDescription)"
            showDeleteConfirmation = false
        }
    }

    func cancelDelete() {
        meetingToDelete = nil
        showDeleteConfirmation = false
    }

    func meetingForCalendarEvent(_ event: UnifiedCalendarEvent) -> MeetingRecord? {
        let eventId = event.googleEventId ?? event.id
        return meetings.first(where: { $0.calendarEventId == eventId })
    }

    // MARK: - Import Recording

    func importRecording(url: URL) async -> MeetingRecord? {
        let importer = AudioFileImporter()
        let storageManager = StorageManager.shared

        do {
            let info = try await importer.importFile(url: url)

            let destDir = storageManager.recordingsDirectory
            let destURL = destDir.appendingPathComponent(url.lastPathComponent)

            if !FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.copyItem(at: url, to: destURL)
            }

            let meeting = MeetingRecord(
                id: UUID().uuidString,
                title: url.deletingPathExtension().lastPathComponent,
                startedAt: selectedDate,
                endedAt: selectedDate.addingTimeInterval(info.duration),
                mode: "playback",
                status: "completed",
                createdAt: Date(),
                sourceFilePath: destURL.path,
                speakerCount: nil,
                calendarEventId: nil,
                calendarTitle: nil
            )

            try await meetingRepository.create(meeting)
            meetings.append(meeting)
            return meeting
        } catch {
            errorMessage = "Failed to import recording: \(error.localizedDescription)"
            return nil
        }
    }

    func updateMeetingDate(_ meeting: MeetingRecord, newDate: Date) async {
        let duration = meeting.endedAt.map { $0.timeIntervalSince(meeting.startedAt) } ?? 0
        let updated = MeetingRecord(
            id: meeting.id,
            title: meeting.title,
            startedAt: newDate,
            endedAt: newDate.addingTimeInterval(duration),
            mode: meeting.mode,
            status: meeting.status,
            createdAt: meeting.createdAt,
            sourceFilePath: meeting.sourceFilePath,
            speakerCount: meeting.speakerCount,
            calendarEventId: meeting.calendarEventId,
            calendarTitle: meeting.calendarTitle
        )

        do {
            try await meetingRepository.update(updated)
            if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
                meetings[index] = updated
            }
        } catch {
            errorMessage = "Failed to update meeting: \(error.localizedDescription)"
        }
    }

    // MARK: - Formatting

    func formatDuration(_ meeting: MeetingRecord) -> String {
        guard let endedAt = meeting.endedAt else { return "--:--" }
        let duration = Int(endedAt.timeIntervalSince(meeting.startedAt))
        let hours = duration / 3600
        let minutes = (duration % 3600) / 60
        let seconds = duration % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func formatTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    // MARK: - Navigation

    func navigateMonth(by offset: Int) {
        if let newDate = calendar.date(byAdding: .month, value: offset, to: selectedDate) {
            selectedDate = newDate
        }
    }

    func navigateWeek(by offset: Int) {
        if let newDate = calendar.date(byAdding: .weekOfYear, value: offset, to: selectedDate) {
            selectedDate = newDate
        }
    }

    func navigateDay(by offset: Int) {
        if let newDate = calendar.date(byAdding: .day, value: offset, to: selectedDate) {
            selectedDate = newDate
        }
    }

    func goToToday() {
        selectedDate = Date()
    }

    var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedDate)
    }

    var weekRangeString: String {
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)),
              let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let endFormatter = DateFormatter()
        endFormatter.dateFormat = "MMM d, yyyy"
        return "\(formatter.string(from: weekStart)) - \(endFormatter.string(from: weekEnd))"
    }

    var selectedDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: selectedDate)
    }

    // MARK: - Calendar Grid Helpers

    func daysInMonthGrid() -> [Date?] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)),
              let range = calendar.range(of: .day, in: .month, for: selectedDate) else {
            return []
        }

        let weekday = calendar.component(.weekday, from: monthStart)
        // Monday-based: weekday 1 (Sun) = 6, weekday 2 (Mon) = 0, etc.
        let mondayOffset = (weekday + 5) % 7
        var days: [Date?] = Array(repeating: nil, count: mondayOffset)

        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                days.append(date)
            }
        }

        // Pad to complete the last week
        while days.count % 7 != 0 {
            days.append(nil)
        }

        return days
    }

    func daysInWeek() -> [Date] {
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)) else {
            return []
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    func isSelected(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: selectedDate)
    }

    func eventCountForDate(_ date: Date) -> Int {
        meetingsForDate(date).count + calendarEventsForDate(date).count
    }

    // MARK: - Document Linking

    func linkedDocuments(for meetingId: String) async -> [DocumentRecord] {
        do {
            return try await documentRepository.fetchDocuments(forMeetingId: meetingId)
        } catch {
            errorMessage = "Failed to load linked documents: \(error.localizedDescription)"
            return []
        }
    }

    func allDocuments() async -> [DocumentRecord] {
        do {
            return try await documentRepository.listAll()
        } catch {
            errorMessage = "Failed to load documents: \(error.localizedDescription)"
            return []
        }
    }

    func linkDocument(documentId: String, to meetingId: String) async {
        do {
            try await documentRepository.linkDocument(documentId: documentId, meetingId: meetingId)
        } catch {
            errorMessage = "Failed to link document: \(error.localizedDescription)"
        }
    }

    func unlinkDocument(documentId: String) async {
        do {
            try await documentRepository.unlinkDocument(documentId: documentId)
        } catch {
            errorMessage = "Failed to unlink document: \(error.localizedDescription)"
        }
    }

    // MARK: - Private

    private func visibleDateRange() -> (start: Date, end: Date) {
        let comps = calendar.dateComponents([.year, .month], from: selectedDate)
        let monthStart = calendar.date(from: comps) ?? selectedDate
        let start = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        let end = calendar.date(byAdding: .month, value: 2, to: monthStart) ?? monthStart
        return (start, end)
    }
}
