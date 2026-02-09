import Foundation
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "CalendarSync")

// MARK: - SyncToken Store Protocol

protocol SyncTokenStoreProtocol: Sendable {
    func getSyncToken() -> String?
    func setSyncToken(_ token: String?)
}

// MARK: - UserDefaults SyncToken Store

final class UserDefaultsSyncTokenStore: SyncTokenStoreProtocol, @unchecked Sendable {
    private let key = "com.gophy.calendar.syncToken"
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func getSyncToken() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return defaults.string(forKey: key)
    }

    func setSyncToken(_ token: String?) {
        lock.lock()
        defer { lock.unlock() }
        if let token = token {
            defaults.set(token, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - CalendarSyncService

actor CalendarSyncService {
    private let apiClient: any GoogleCalendarAPIClientProtocol
    private let eventKitService: any EventKitServiceProtocol
    private let syncTokenStore: any SyncTokenStoreProtocol
    private let pollingInterval: TimeInterval

    private var cachedEvents: [UnifiedCalendarEvent] = []
    private var pollingTask: Task<Void, Never>?
    private var streamContinuation: AsyncStream<[UnifiedCalendarEvent]>.Continuation?
    private(set) var lastGoogleError: (any Error)?

    init(
        apiClient: any GoogleCalendarAPIClientProtocol,
        eventKitService: any EventKitServiceProtocol,
        syncTokenStore: any SyncTokenStoreProtocol = UserDefaultsSyncTokenStore(),
        pollingInterval: TimeInterval = 300
    ) {
        self.apiClient = apiClient
        self.eventKitService = eventKitService
        self.syncTokenStore = syncTokenStore
        self.pollingInterval = pollingInterval
    }

    // MARK: - Public API

    func eventStream() -> AsyncStream<[UnifiedCalendarEvent]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [UnifiedCalendarEvent].self)
        streamContinuation = continuation
        return stream
    }

    func start() {
        guard pollingTask == nil else { return }

        let interval = pollingInterval
        pollingTask = Task {
            while !Task.isCancelled {
                do {
                    let events = try await self.syncNow()
                    await self.emitEvents(events)
                } catch {
                    logger.warning("Polling sync failed: \(error.localizedDescription, privacy: .public)")
                }

                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    break
                }
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func syncNow() async throws -> [UnifiedCalendarEvent] {
        let now = Date()
        let timeMin = now.addingTimeInterval(-7 * 24 * 3600)
        let timeMax = now.addingTimeInterval(30 * 24 * 3600)

        // Fetch EventKit events (always fresh)
        let localEvents = eventKitService.fetchUpcomingEvents(
            from: timeMin,
            to: timeMax,
            calendars: nil
        )

        // Fetch Google Calendar events (with sync token if available)
        var googleEvents: [CalendarEvent] = []
        do {
            let calendars = try await apiClient.fetchCalendarList()
            let primaryId = calendars.first(where: { $0.primary == true })?.id ?? "primary"

            let syncToken = syncTokenStore.getSyncToken()
            var response: EventListResponse

            do {
                if let token = syncToken {
                    response = try await apiClient.fetchEvents(
                        calendarId: primaryId,
                        timeMin: nil,
                        timeMax: nil,
                        syncToken: token,
                        pageToken: nil
                    )
                } else {
                    response = try await apiClient.fetchEvents(
                        calendarId: primaryId,
                        timeMin: timeMin,
                        timeMax: timeMax,
                        syncToken: nil,
                        pageToken: nil
                    )
                }
            } catch let error as CalendarAPIError where error.isSyncTokenExpired {
                logger.info("Sync token expired, performing full re-sync")
                syncTokenStore.setSyncToken(nil)
                response = try await apiClient.fetchEvents(
                    calendarId: primaryId,
                    timeMin: timeMin,
                    timeMax: timeMax,
                    syncToken: nil,
                    pageToken: nil
                )
            }

            googleEvents = response.events
            if let nextToken = response.nextSyncToken {
                syncTokenStore.setSyncToken(nextToken)
            }
        } catch {
            logger.warning("Google Calendar fetch failed: \(error.localizedDescription, privacy: .public)")
            lastGoogleError = error
        }

        let merged = mergeEvents(google: googleEvents, local: localEvents)
        cachedEvents = merged
        return merged
    }

    func currentEvents() -> [UnifiedCalendarEvent] {
        cachedEvents
    }

    // MARK: - Private

    private func clearContinuation() {
        streamContinuation = nil
    }

    private func emitEvents(_ events: [UnifiedCalendarEvent]) {
        streamContinuation?.yield(events)
    }

    private func mergeEvents(
        google: [CalendarEvent],
        local: [LocalCalendarEvent]
    ) -> [UnifiedCalendarEvent] {
        var result: [UnifiedCalendarEvent] = []
        var matchedLocalIds = Set<String>()

        // Add Google events first (richer data)
        for gEvent in google {
            guard let startDate = gEvent.startDate, let endDate = gEvent.endDate else {
                continue
            }

            let attendees = (gEvent.attendees ?? []).compactMap { a -> MeetingAttendee? in
                guard let email = a.email else { return nil }
                return MeetingAttendee(
                    email: email,
                    displayName: a.displayName,
                    responseStatus: a.responseStatus,
                    isSelf: a.isSelf ?? false
                )
            }

            let unified = UnifiedCalendarEvent(
                id: "google-\(gEvent.id)",
                title: gEvent.summary ?? "",
                startDate: startDate,
                endDate: endDate,
                location: gEvent.location,
                isAllDay: gEvent.start?.isAllDay ?? false,
                meetingLink: gEvent.meetingLink,
                attendees: attendees,
                source: .google,
                googleEventId: gEvent.id,
                calendarId: nil
            )
            result.append(unified)

            // Mark matching local events as consumed
            for localEvent in local {
                if eventsMatch(googleTitle: gEvent.summary, googleStart: startDate,
                               localTitle: localEvent.title, localStart: localEvent.startDate) {
                    matchedLocalIds.insert(localEvent.identifier)
                }
            }
        }

        // Add unmatched EventKit events
        for localEvent in local where !matchedLocalIds.contains(localEvent.identifier) {
            let unified = UnifiedCalendarEvent(
                id: "eventkit-\(localEvent.identifier)",
                title: localEvent.title,
                startDate: localEvent.startDate,
                endDate: localEvent.endDate,
                location: localEvent.location,
                isAllDay: localEvent.isAllDay,
                meetingLink: localEvent.url?.absoluteString,
                attendees: [],
                source: .eventKit,
                googleEventId: nil,
                calendarId: nil
            )
            result.append(unified)
        }

        return result.sorted { $0.startDate < $1.startDate }
    }

    private func eventsMatch(
        googleTitle: String?,
        googleStart: Date,
        localTitle: String,
        localStart: Date
    ) -> Bool {
        guard let gTitle = googleTitle else { return false }
        let titleMatch = gTitle.lowercased() == localTitle.lowercased()
        let timeDiff = abs(googleStart.timeIntervalSince(localStart))
        let timeMatch = timeDiff < 60 // within 1 minute
        return titleMatch && timeMatch
    }
}

// MARK: - CalendarAPIError Extension

extension CalendarAPIError {
    var isSyncTokenExpired: Bool {
        if case .syncTokenExpired = self {
            return true
        }
        return false
    }
}
