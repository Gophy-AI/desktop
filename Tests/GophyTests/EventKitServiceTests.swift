import Testing
import Foundation
@testable import Gophy

// MARK: - Mock EventKitService

final class MockEventKitService: EventKitServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _authorizationStatus: Bool = true
    private var _calendars: [LocalCalendar] = []
    private var _events: [LocalCalendarEvent] = []
    private var _requestAccessCallCount = 0
    private var _fetchCalendarsCallCount = 0
    private var _fetchEventsCallCount = 0
    private var _changeNotificationContinuation: AsyncStream<Void>.Continuation?

    var authorizationStatus: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _authorizationStatus
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _authorizationStatus = newValue
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

    var requestAccessCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _requestAccessCallCount
    }

    var fetchCalendarsCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _fetchCalendarsCallCount
    }

    var fetchEventsCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _fetchEventsCallCount
    }

    func requestAccess() async throws -> Bool {
        let status = incrementAndGetStatus()
        return status
    }

    private func incrementAndGetStatus() -> Bool {
        lock.lock()
        _requestAccessCallCount += 1
        let status = _authorizationStatus
        lock.unlock()
        return status
    }

    func fetchCalendars() -> [LocalCalendar] {
        lock.lock()
        _fetchCalendarsCallCount += 1
        let result = _calendars
        lock.unlock()
        return result
    }

    func fetchUpcomingEvents(from: Date, to: Date, calendars: [String]?) -> [LocalCalendarEvent] {
        lock.lock()
        _fetchEventsCallCount += 1
        var result = _events
        lock.unlock()

        result = result.filter { event in
            event.startDate >= from && event.startDate <= to
        }

        if let calendars = calendars {
            result = result.filter { event in
                calendars.contains(event.calendarTitle)
            }
        }

        return result.sorted { $0.startDate < $1.startDate }
    }

    func observe() -> AsyncStream<Void> {
        AsyncStream { continuation in
            lock.lock()
            _changeNotificationContinuation = continuation
            lock.unlock()
        }
    }

    func triggerChangeNotification() {
        lock.lock()
        let continuation = _changeNotificationContinuation
        lock.unlock()
        continuation?.yield()
    }
}

// MARK: - Tests

@Suite("EventKitService Tests")
struct EventKitServiceTests {

    @Test("requestAccess returns authorization status when granted")
    func testRequestAccessReturnsTrue() async throws {
        let service = MockEventKitService()
        service.authorizationStatus = true

        let granted = try await service.requestAccess()
        #expect(granted == true)
        #expect(service.requestAccessCallCount == 1)
    }

    @Test("requestAccess returns false when denied")
    func testRequestAccessReturnsFalse() async throws {
        let service = MockEventKitService()
        service.authorizationStatus = false

        let granted = try await service.requestAccess()
        #expect(granted == false)
        #expect(service.requestAccessCallCount == 1)
    }

    @Test("fetchCalendars returns list of local calendars")
    func testFetchCalendarsReturnsList() {
        let service = MockEventKitService()
        service.calendars = [
            LocalCalendar(
                identifier: "cal-1",
                title: "Work",
                type: .local,
                source: "Local",
                color: "#FF5733"
            ),
            LocalCalendar(
                identifier: "cal-2",
                title: "Personal",
                type: .local,
                source: "Local",
                color: "#3357FF"
            )
        ]

        let calendars = service.fetchCalendars()

        #expect(calendars.count == 2)
        #expect(calendars[0].title == "Work")
        #expect(calendars[1].title == "Personal")
        #expect(service.fetchCalendarsCallCount == 1)
    }

    @Test("fetchCalendars returns empty list when no calendars available")
    func testFetchCalendarsReturnsEmpty() {
        let service = MockEventKitService()
        service.calendars = []

        let calendars = service.fetchCalendars()

        #expect(calendars.isEmpty)
        #expect(service.fetchCalendarsCallCount == 1)
    }

    @Test("fetchUpcomingEvents returns events sorted by startDate")
    func testFetchUpcomingEventsSortedByStartDate() {
        let service = MockEventKitService()

        let now = Date()
        let event1 = LocalCalendarEvent(
            identifier: "event-1",
            title: "Meeting 1",
            startDate: now.addingTimeInterval(3600),
            endDate: now.addingTimeInterval(7200),
            location: nil,
            notes: nil,
            calendarTitle: "Work",
            isAllDay: false,
            url: nil,
            organizer: nil
        )
        let event2 = LocalCalendarEvent(
            identifier: "event-2",
            title: "Meeting 2",
            startDate: now.addingTimeInterval(1800),
            endDate: now.addingTimeInterval(5400),
            location: nil,
            notes: nil,
            calendarTitle: "Work",
            isAllDay: false,
            url: nil,
            organizer: nil
        )

        service.events = [event1, event2]

        let events = service.fetchUpcomingEvents(
            from: now,
            to: now.addingTimeInterval(86400),
            calendars: nil
        )

        #expect(events.count == 2)
        #expect(events[0].identifier == "event-2")
        #expect(events[1].identifier == "event-1")
        #expect(service.fetchEventsCallCount == 1)
    }

    @Test("fetchUpcomingEvents filters events by date range")
    func testFetchUpcomingEventsFiltersByDateRange() {
        let service = MockEventKitService()

        let now = Date()
        let event1 = LocalCalendarEvent(
            identifier: "event-1",
            title: "Meeting 1",
            startDate: now.addingTimeInterval(3600),
            endDate: now.addingTimeInterval(7200),
            location: nil,
            notes: nil,
            calendarTitle: "Work",
            isAllDay: false,
            url: nil,
            organizer: nil
        )
        let event2 = LocalCalendarEvent(
            identifier: "event-2",
            title: "Meeting 2",
            startDate: now.addingTimeInterval(86400 * 2),
            endDate: now.addingTimeInterval(86400 * 2 + 3600),
            location: nil,
            notes: nil,
            calendarTitle: "Work",
            isAllDay: false,
            url: nil,
            organizer: nil
        )

        service.events = [event1, event2]

        let events = service.fetchUpcomingEvents(
            from: now,
            to: now.addingTimeInterval(86400),
            calendars: nil
        )

        #expect(events.count == 1)
        #expect(events[0].identifier == "event-1")
    }

    @Test("fetchUpcomingEvents filters by calendar identifiers")
    func testFetchUpcomingEventsFiltersByCalendar() {
        let service = MockEventKitService()

        let now = Date()
        let workEvent = LocalCalendarEvent(
            identifier: "work-event",
            title: "Work Meeting",
            startDate: now.addingTimeInterval(3600),
            endDate: now.addingTimeInterval(7200),
            location: nil,
            notes: nil,
            calendarTitle: "Work",
            isAllDay: false,
            url: nil,
            organizer: nil
        )
        let personalEvent = LocalCalendarEvent(
            identifier: "personal-event",
            title: "Personal Meeting",
            startDate: now.addingTimeInterval(1800),
            endDate: now.addingTimeInterval(5400),
            location: nil,
            notes: nil,
            calendarTitle: "Personal",
            isAllDay: false,
            url: nil,
            organizer: nil
        )

        service.events = [workEvent, personalEvent]

        let events = service.fetchUpcomingEvents(
            from: now,
            to: now.addingTimeInterval(86400),
            calendars: ["Work"]
        )

        #expect(events.count == 1)
        #expect(events[0].identifier == "work-event")
    }

    @Test("events from Google, iCloud, Exchange calendars are unified")
    func testEventsFromMultipleSourcesUnified() {
        let service = MockEventKitService()

        service.calendars = [
            LocalCalendar(
                identifier: "google-cal",
                title: "Google Calendar",
                type: .calDAV,
                source: "Google",
                color: "#4285f4"
            ),
            LocalCalendar(
                identifier: "icloud-cal",
                title: "iCloud Calendar",
                type: .calDAV,
                source: "iCloud",
                color: "#007AFF"
            ),
            LocalCalendar(
                identifier: "exchange-cal",
                title: "Exchange Calendar",
                type: .exchange,
                source: "Exchange",
                color: "#0078D4"
            )
        ]

        let calendars = service.fetchCalendars()

        #expect(calendars.count == 3)
        let types = Set(calendars.map { $0.type })
        #expect(types.contains(.calDAV))
        #expect(types.contains(.exchange))
    }

    @Test("observe returns AsyncStream that yields on change notification")
    func testObserveTriggersCallback() async throws {
        let service = MockEventKitService()

        let stream = service.observe()

        var changeCount = 0
        let task = Task {
            for await _ in stream {
                changeCount += 1
                if changeCount >= 2 {
                    break
                }
            }
        }

        try await Task.sleep(nanoseconds: 10_000_000)
        service.triggerChangeNotification()
        try await Task.sleep(nanoseconds: 10_000_000)
        service.triggerChangeNotification()
        try await Task.sleep(nanoseconds: 10_000_000)

        await task.value

        #expect(changeCount == 2)
    }

    @Test("fetchUpcomingEvents includes all event properties")
    func testFetchEventsIncludesAllProperties() {
        let service = MockEventKitService()

        let now = Date()
        let event = LocalCalendarEvent(
            identifier: "event-1",
            title: "Team Standup",
            startDate: now.addingTimeInterval(3600),
            endDate: now.addingTimeInterval(5400),
            location: "Conference Room A",
            notes: "Discuss sprint goals",
            calendarTitle: "Work",
            isAllDay: false,
            url: URL(string: "https://meet.google.com/abc-defg"),
            organizer: "alice@example.com"
        )

        service.events = [event]

        let events = service.fetchUpcomingEvents(
            from: now,
            to: now.addingTimeInterval(86400),
            calendars: nil
        )

        #expect(events.count == 1)
        let retrieved = events[0]
        #expect(retrieved.title == "Team Standup")
        #expect(retrieved.location == "Conference Room A")
        #expect(retrieved.notes == "Discuss sprint goals")
        #expect(retrieved.isAllDay == false)
        #expect(retrieved.url?.absoluteString == "https://meet.google.com/abc-defg")
        #expect(retrieved.organizer == "alice@example.com")
    }

    @Test("fetchUpcomingEvents handles all-day events")
    func testFetchEventsHandlesAllDayEvents() {
        let service = MockEventKitService()

        let now = Date()
        let allDayEvent = LocalCalendarEvent(
            identifier: "all-day",
            title: "Holiday",
            startDate: now.addingTimeInterval(3600),
            endDate: now.addingTimeInterval(86400 + 3600),
            location: nil,
            notes: nil,
            calendarTitle: "Personal",
            isAllDay: true,
            url: nil,
            organizer: nil
        )

        service.events = [allDayEvent]

        let events = service.fetchUpcomingEvents(
            from: now,
            to: now.addingTimeInterval(86400 * 2),
            calendars: nil
        )

        #expect(events.count == 1)
        #expect(events[0].isAllDay == true)
    }
}
