import Testing
import Foundation
@testable import Gophy

// MARK: - Mock GoogleCalendarAPIClient

actor MockCalendarAPIClient: GoogleCalendarAPIClientProtocol {
    private var _calendarList: [CalendarInfo] = []
    private var _eventResponses: [EventListResponse] = []
    private var _eventResponseIndex = 0
    private var _fetchEventsCallCount = 0
    private var _lastSyncToken: String?
    private var _shouldThrow410 = false
    private var _shouldThrowError: (any Error)?

    var fetchEventsCallCount: Int {
        get { _fetchEventsCallCount }
    }

    var lastSyncToken: String? {
        get { _lastSyncToken }
    }

    func setCalendarList(_ list: [CalendarInfo]) {
        _calendarList = list
    }

    func setEventResponses(_ responses: [EventListResponse]) {
        _eventResponses = responses
        _eventResponseIndex = 0
    }

    func setShouldThrow410(_ should: Bool) {
        _shouldThrow410 = should
    }

    func setShouldThrowError(_ error: (any Error)?) {
        _shouldThrowError = error
    }

    func resetEventResponseIndex() {
        _eventResponseIndex = 0
    }

    func fetchCalendarList() async throws -> [CalendarInfo] {
        if let error = _shouldThrowError {
            throw error
        }
        return _calendarList
    }

    func fetchEvents(
        calendarId: String,
        timeMin: Date?,
        timeMax: Date?,
        syncToken: String?,
        pageToken: String?
    ) async throws -> EventListResponse {
        _fetchEventsCallCount += 1
        _lastSyncToken = syncToken

        if let error = _shouldThrowError {
            throw error
        }

        if _shouldThrow410 && syncToken != nil {
            _shouldThrow410 = false
            throw CalendarAPIError.syncTokenExpired
        }

        guard _eventResponseIndex < _eventResponses.count else {
            return EventListResponse(items: [], nextSyncToken: nil, nextPageToken: nil)
        }

        let response = _eventResponses[_eventResponseIndex]
        _eventResponseIndex += 1
        return response
    }

    func patchEvent(calendarId: String, eventId: String, description: String) async throws {}
    func patchExtendedProperties(calendarId: String, eventId: String, properties: [String: String]) async throws {}
}

// MARK: - Mock EventKitService for Sync Tests

final class MockEventKitServiceForSync: EventKitServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [LocalCalendarEvent] = []
    private var _calendars: [LocalCalendar] = []
    private var _changeContinuation: AsyncStream<Void>.Continuation?

    var events: [LocalCalendarEvent] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _events
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _events = newValue
        }
    }

    var calendars: [LocalCalendar] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _calendars
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _calendars = newValue
        }
    }

    func requestAccess() async throws -> Bool {
        return true
    }

    func fetchCalendars() -> [LocalCalendar] {
        lock.lock()
        defer { lock.unlock() }
        return _calendars
    }

    func fetchUpcomingEvents(from: Date, to: Date, calendars: [String]?) -> [LocalCalendarEvent] {
        lock.lock()
        let result = _events
        lock.unlock()

        return result
            .filter { $0.startDate >= from && $0.startDate <= to }
            .sorted { $0.startDate < $1.startDate }
    }

    func observe() -> AsyncStream<Void> {
        AsyncStream { continuation in
            lock.lock()
            _changeContinuation = continuation
            lock.unlock()
        }
    }

    func triggerChange() {
        lock.lock()
        let cont = _changeContinuation
        lock.unlock()
        cont?.yield()
    }
}

// MARK: - Mock SyncToken Store

final class MockSyncTokenStore: SyncTokenStoreProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _token: String?

    var token: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _token
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _token = newValue
        }
    }

    func getSyncToken() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return _token
    }

    func setSyncToken(_ token: String?) {
        lock.lock()
        defer { lock.unlock() }
        _token = token
    }
}

// MARK: - Tests

@Suite("CalendarSyncService Tests")
struct CalendarSyncServiceTests {

    // MARK: - Helpers

    private func makeGoogleEvent(
        id: String,
        summary: String,
        startDate: Date,
        endDate: Date,
        meetLink: String? = nil,
        attendees: [Attendee]? = nil
    ) -> CalendarEvent {
        let start = EventDateTime(
            dateTime: ISO8601DateFormatter().string(from: startDate),
            dateValue: nil,
            timeZone: nil
        )
        let end = EventDateTime(
            dateTime: ISO8601DateFormatter().string(from: endDate),
            dateValue: nil,
            timeZone: nil
        )
        let conferenceData: ConferenceData?
        if let meetLink = meetLink {
            conferenceData = ConferenceData(entryPoints: [
                EntryPoint(uri: meetLink, label: nil, entryPointType: "video")
            ])
        } else {
            conferenceData = nil
        }

        return CalendarEvent(
            id: id,
            summary: summary,
            description: nil,
            start: start,
            end: end,
            location: nil,
            status: "confirmed",
            attendees: attendees,
            conferenceData: conferenceData,
            hangoutLink: nil,
            htmlLink: "https://calendar.google.com/event?id=\(id)",
            organizer: nil,
            extendedProperties: nil
        )
    }

    private func makeLocalEvent(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        calendarTitle: String = "Work"
    ) -> LocalCalendarEvent {
        LocalCalendarEvent(
            identifier: id,
            title: title,
            startDate: startDate,
            endDate: endDate,
            location: nil,
            notes: nil,
            calendarTitle: calendarTitle,
            isAllDay: false,
            url: nil,
            organizer: nil
        )
    }

    // MARK: - Initial Sync Tests

    @Test("Initial sync fetches all events and stores syncToken")
    func testInitialSyncFetchesEventsAndStoresSyncToken() async throws {
        let apiClient = MockCalendarAPIClient()
        let eventKitService = MockEventKitServiceForSync()
        let tokenStore = MockSyncTokenStore()

        let now = Date()
        let event = makeGoogleEvent(
            id: "g1",
            summary: "Team Standup",
            startDate: now.addingTimeInterval(3600),
            endDate: now.addingTimeInterval(5400)
        )

        await apiClient.setCalendarList([
            CalendarInfo(id: "primary", summary: "My Calendar", primary: true, backgroundColor: nil)
        ])
        await apiClient.setEventResponses([
            EventListResponse(items: [event], nextSyncToken: "token-1", nextPageToken: nil)
        ])

        let service = CalendarSyncService(
            apiClient: apiClient,
            eventKitService: eventKitService,
            syncTokenStore: tokenStore,
            pollingInterval: 300
        )

        let events = try await service.syncNow()

        #expect(events.count == 1)
        #expect(events[0].title == "Team Standup")
        #expect(tokenStore.token == "token-1")
    }

    // MARK: - Incremental Sync Tests

    @Test("Incremental sync uses syncToken and returns only changed events")
    func testIncrementalSyncUsesSyncToken() async throws {
        let apiClient = MockCalendarAPIClient()
        let eventKitService = MockEventKitServiceForSync()
        let tokenStore = MockSyncTokenStore()
        tokenStore.token = "existing-token"

        let now = Date()
        let changedEvent = makeGoogleEvent(
            id: "g2",
            summary: "Updated Meeting",
            startDate: now.addingTimeInterval(7200),
            endDate: now.addingTimeInterval(9000)
        )

        await apiClient.setCalendarList([
            CalendarInfo(id: "primary", summary: "My Calendar", primary: true, backgroundColor: nil)
        ])
        await apiClient.setEventResponses([
            EventListResponse(items: [changedEvent], nextSyncToken: "token-2", nextPageToken: nil)
        ])

        let service = CalendarSyncService(
            apiClient: apiClient,
            eventKitService: eventKitService,
            syncTokenStore: tokenStore,
            pollingInterval: 300
        )

        let events = try await service.syncNow()

        #expect(events.count == 1)
        #expect(events[0].title == "Updated Meeting")
        #expect(tokenStore.token == "token-2")

        let lastToken = await apiClient.lastSyncToken
        #expect(lastToken == "existing-token")
    }

    // MARK: - 410 GONE Re-sync Tests

    @Test("syncToken expiry (410) triggers full re-sync")
    func testSyncTokenExpiryTriggersFullResync() async throws {
        let apiClient = MockCalendarAPIClient()
        let eventKitService = MockEventKitServiceForSync()
        let tokenStore = MockSyncTokenStore()
        tokenStore.token = "stale-token"

        let now = Date()
        let freshEvent = makeGoogleEvent(
            id: "g3",
            summary: "Fresh Event",
            startDate: now.addingTimeInterval(3600),
            endDate: now.addingTimeInterval(5400)
        )

        await apiClient.setCalendarList([
            CalendarInfo(id: "primary", summary: "Calendar", primary: true, backgroundColor: nil)
        ])
        await apiClient.setShouldThrow410(true)
        await apiClient.setEventResponses([
            EventListResponse(items: [freshEvent], nextSyncToken: "new-token", nextPageToken: nil)
        ])

        let service = CalendarSyncService(
            apiClient: apiClient,
            eventKitService: eventKitService,
            syncTokenStore: tokenStore,
            pollingInterval: 300
        )

        let events = try await service.syncNow()

        #expect(events.count == 1)
        #expect(events[0].title == "Fresh Event")
        #expect(tokenStore.token == "new-token")
    }

    // MARK: - Event Merging Tests

    @Test("Merged event list combines EventKit and Google API events without duplicates")
    func testMergedEventListDeduplicates() async throws {
        let apiClient = MockCalendarAPIClient()
        let eventKitService = MockEventKitServiceForSync()
        let tokenStore = MockSyncTokenStore()

        let now = Date()
        let meetingStart = now.addingTimeInterval(3600)
        let meetingEnd = now.addingTimeInterval(5400)

        let googleEvent = makeGoogleEvent(
            id: "g1",
            summary: "Team Standup",
            startDate: meetingStart,
            endDate: meetingEnd,
            meetLink: "https://meet.google.com/abc"
        )

        let localEvent = makeLocalEvent(
            id: "ek1",
            title: "Team Standup",
            startDate: meetingStart,
            endDate: meetingEnd
        )

        await apiClient.setCalendarList([
            CalendarInfo(id: "primary", summary: "Calendar", primary: true, backgroundColor: nil)
        ])
        await apiClient.setEventResponses([
            EventListResponse(items: [googleEvent], nextSyncToken: "t1", nextPageToken: nil)
        ])

        eventKitService.events = [localEvent]

        let service = CalendarSyncService(
            apiClient: apiClient,
            eventKitService: eventKitService,
            syncTokenStore: tokenStore,
            pollingInterval: 300
        )

        let events = try await service.syncNow()

        let standups = events.filter { $0.title == "Team Standup" }
        #expect(standups.count == 1)
        #expect(standups[0].meetingLink == "https://meet.google.com/abc")
        #expect(standups[0].source == .google)
    }

    @Test("EventKit events included when no Google match exists")
    func testEventKitOnlyEventsIncluded() async throws {
        let apiClient = MockCalendarAPIClient()
        let eventKitService = MockEventKitServiceForSync()
        let tokenStore = MockSyncTokenStore()

        let now = Date()
        let localEvent = makeLocalEvent(
            id: "ek1",
            title: "iCloud Meeting",
            startDate: now.addingTimeInterval(3600),
            endDate: now.addingTimeInterval(5400),
            calendarTitle: "iCloud"
        )

        await apiClient.setCalendarList([
            CalendarInfo(id: "primary", summary: "Calendar", primary: true, backgroundColor: nil)
        ])
        await apiClient.setEventResponses([
            EventListResponse(items: [], nextSyncToken: "t1", nextPageToken: nil)
        ])

        eventKitService.events = [localEvent]

        let service = CalendarSyncService(
            apiClient: apiClient,
            eventKitService: eventKitService,
            syncTokenStore: tokenStore,
            pollingInterval: 300
        )

        let events = try await service.syncNow()

        #expect(events.count == 1)
        #expect(events[0].title == "iCloud Meeting")
        #expect(events[0].source == .eventKit)
    }

    // MARK: - Polling Tests

    @Test("Polling at configured interval triggers sync")
    func testPollingTriggersSync() async throws {
        let apiClient = MockCalendarAPIClient()
        let eventKitService = MockEventKitServiceForSync()
        let tokenStore = MockSyncTokenStore()

        let now = Date()
        let event = makeGoogleEvent(
            id: "g1",
            summary: "Recurring Standup",
            startDate: now.addingTimeInterval(3600),
            endDate: now.addingTimeInterval(5400)
        )

        await apiClient.setCalendarList([
            CalendarInfo(id: "primary", summary: "Calendar", primary: true, backgroundColor: nil)
        ])
        await apiClient.setEventResponses([
            EventListResponse(items: [event], nextSyncToken: "t1", nextPageToken: nil),
            EventListResponse(items: [event], nextSyncToken: "t2", nextPageToken: nil),
            EventListResponse(items: [event], nextSyncToken: "t3", nextPageToken: nil),
        ])

        let service = CalendarSyncService(
            apiClient: apiClient,
            eventKitService: eventKitService,
            syncTokenStore: tokenStore,
            pollingInterval: 0.1
        )

        let stream = await service.eventStream()
        await service.start()

        var receivedCount = 0
        for await _ in stream {
            receivedCount += 1
            if receivedCount >= 2 {
                break
            }
        }

        await service.stop()

        #expect(receivedCount >= 2)
    }

    // MARK: - Failure Resilience Tests

    @Test("Sync failure does not lose previously fetched events")
    func testSyncFailurePreservesPreviousEvents() async throws {
        let apiClient = MockCalendarAPIClient()
        let eventKitService = MockEventKitServiceForSync()
        let tokenStore = MockSyncTokenStore()

        let now = Date()
        let event = makeGoogleEvent(
            id: "g1",
            summary: "Important Meeting",
            startDate: now.addingTimeInterval(3600),
            endDate: now.addingTimeInterval(5400)
        )

        await apiClient.setCalendarList([
            CalendarInfo(id: "primary", summary: "Calendar", primary: true, backgroundColor: nil)
        ])
        await apiClient.setEventResponses([
            EventListResponse(items: [event], nextSyncToken: "t1", nextPageToken: nil)
        ])

        let service = CalendarSyncService(
            apiClient: apiClient,
            eventKitService: eventKitService,
            syncTokenStore: tokenStore,
            pollingInterval: 300
        )

        let firstEvents = try await service.syncNow()
        #expect(firstEvents.count == 1)

        await apiClient.setShouldThrowError(CalendarAPIError.networkError("Connection lost"))
        await apiClient.resetEventResponseIndex()

        let preservedEvents = await service.currentEvents()
        #expect(preservedEvents.count == 1)
        #expect(preservedEvents[0].title == "Important Meeting")
    }

    // MARK: - Google signed-out graceful handling

    @Test("Sync works with EventKit only when Google API fails")
    func testSyncWorksWithEventKitOnlyWhenGoogleFails() async throws {
        let apiClient = MockCalendarAPIClient()
        let eventKitService = MockEventKitServiceForSync()
        let tokenStore = MockSyncTokenStore()

        let now = Date()
        let localEvent = makeLocalEvent(
            id: "ek1",
            title: "Local Event",
            startDate: now.addingTimeInterval(3600),
            endDate: now.addingTimeInterval(5400)
        )

        eventKitService.events = [localEvent]
        await apiClient.setShouldThrowError(GoogleAuthError.notSignedIn)

        let service = CalendarSyncService(
            apiClient: apiClient,
            eventKitService: eventKitService,
            syncTokenStore: tokenStore,
            pollingInterval: 300
        )

        let events = try await service.syncNow()

        #expect(events.count == 1)
        #expect(events[0].title == "Local Event")
        #expect(events[0].source == .eventKit)
    }
}
