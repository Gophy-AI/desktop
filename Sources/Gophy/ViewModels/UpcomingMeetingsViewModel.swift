import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "UpcomingMeetings")

// MARK: - Protocol for CalendarSyncService

protocol CalendarSyncServiceProtocol: Sendable {
    func eventStream() async -> AsyncStream<[UnifiedCalendarEvent]>
    func syncNow() async throws -> [UnifiedCalendarEvent]
    func currentEvents() async -> [UnifiedCalendarEvent]
    func start() async
    func stop() async
}

extension CalendarSyncService: CalendarSyncServiceProtocol {}

// MARK: - UpcomingMeetingsViewModel

@MainActor
@Observable
final class UpcomingMeetingsViewModel {
    private let calendarSyncService: any CalendarSyncServiceProtocol
    private let now: @Sendable () -> Date
    private var streamTask: Task<Void, Never>?
    private var refreshTimerTask: Task<Void, Never>?

    var upcomingMeetings: [UnifiedCalendarEvent] = []
    var isRefreshing: Bool = false
    var nextMeetingSummary: String?

    init(
        calendarSyncService: any CalendarSyncServiceProtocol,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.calendarSyncService = calendarSyncService
        self.now = now
    }

    func startListening() {
        streamTask = Task {
            let stream = await calendarSyncService.eventStream()
            for await events in stream {
                self.updateMeetings(from: events)
            }
        }

        refreshTimerTask = Task {
            while !Task.isCancelled {
                self.refreshProximityColors()
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }

        Task {
            let events = await calendarSyncService.currentEvents()
            updateMeetings(from: events)
        }
    }

    func stopListening() {
        streamTask?.cancel()
        streamTask = nil
        refreshTimerTask?.cancel()
        refreshTimerTask = nil
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let events = try await calendarSyncService.syncNow()
            updateMeetings(from: events)
        } catch {
            logger.warning("Failed to refresh calendar: \(error.localizedDescription, privacy: .public)")
        }
    }

    func proximityColor(for event: UnifiedCalendarEvent) -> MeetingProximity {
        let currentDate = now()
        let timeUntilStart = event.startDate.timeIntervalSince(currentDate)

        if timeUntilStart <= 0 && event.endDate > currentDate {
            return .now
        } else if timeUntilStart > 0 && timeUntilStart <= 300 {
            return .imminent
        } else if timeUntilStart > 300 && timeUntilStart <= 900 {
            return .soon
        } else {
            return .later
        }
    }

    func shouldShowStartRecording(for event: UnifiedCalendarEvent) -> Bool {
        let currentDate = now()
        let timeUntilStart = event.startDate.timeIntervalSince(currentDate)
        return timeUntilStart <= 120 && event.endDate > currentDate
    }

    func formattedTime(for event: UnifiedCalendarEvent) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: event.startDate)
    }

    func formattedDuration(for event: UnifiedCalendarEvent) -> String {
        let duration = event.endDate.timeIntervalSince(event.startDate)
        let minutes = Int(duration) / 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(remainingMinutes)m"
        }
        return "\(minutes)m"
    }

    // MARK: - Private

    private func updateMeetings(from events: [UnifiedCalendarEvent]) {
        let currentDate = now()
        let tomorrow = currentDate.addingTimeInterval(24 * 3600)

        let upcoming = events
            .filter { event in
                !event.isAllDay
                    && event.endDate > currentDate
                    && event.startDate < tomorrow
            }
            .sorted { $0.startDate < $1.startDate }
            .prefix(5)

        upcomingMeetings = Array(upcoming)

        if let next = upcomingMeetings.first {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            nextMeetingSummary = "\(next.title) at \(formatter.string(from: next.startDate))"
        } else {
            nextMeetingSummary = nil
        }
    }

    private func refreshProximityColors() {
        let currentDate = now()
        let tomorrow = currentDate.addingTimeInterval(24 * 3600)

        upcomingMeetings = upcomingMeetings.filter { event in
            event.endDate > currentDate && event.startDate < tomorrow
        }
    }
}

// MARK: - MeetingProximity

enum MeetingProximity: String, Sendable, Equatable {
    case now
    case imminent
    case soon
    case later
}
