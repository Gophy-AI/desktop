import Testing
import Foundation
@testable import Gophy

// MARK: - Mock CalendarSyncService for AutoStart

actor MockCalendarSyncForAutoStart: CalendarSyncServiceProtocol {
    private var _events: [UnifiedCalendarEvent] = []
    private var _streamContinuation: AsyncStream<[UnifiedCalendarEvent]>.Continuation?

    func setEvents(_ events: [UnifiedCalendarEvent]) {
        _events = events
    }

    func emitEvents(_ events: [UnifiedCalendarEvent]) {
        _events = events
        _streamContinuation?.yield(events)
    }

    func eventStream() -> AsyncStream<[UnifiedCalendarEvent]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [UnifiedCalendarEvent].self)
        _streamContinuation = continuation
        return stream
    }

    func syncNow() async throws -> [UnifiedCalendarEvent] {
        return _events
    }

    func currentEvents() -> [UnifiedCalendarEvent] {
        return _events
    }

    func start() {}
    func stop() {}
}

// MARK: - Mock MeetingStarter

actor MockMeetingStarter: MeetingStarterProtocol {
    private var _startedTitles: [String] = []
    private var _isRecording = false

    var startedTitles: [String] { _startedTitles }
    var isRecording: Bool { _isRecording }

    func startMeeting(title: String, calendarEventId: String?) async throws {
        _startedTitles.append(title)
        _isRecording = true
    }

    func setRecording(_ recording: Bool) {
        _isRecording = recording
    }
}

// MARK: - Mock AutoStart Notifier

actor MockAutoStartNotifier: AutoStartNotifierProtocol {
    private var _notifiedTitles: [String] = []
    private var _shouldSkip = false

    var notifiedTitles: [String] { _notifiedTitles }

    func setShouldSkip(_ skip: Bool) {
        _shouldSkip = skip
    }

    func notifyAndWait(title: String) async -> AutoStartAction {
        _notifiedTitles.append(title)
        return _shouldSkip ? .skip : .startRecording
    }
}

// MARK: - Mock AutoStart Settings

final class MockAutoStartSettings: AutoStartSettingsProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _enabled = true
    private var _onlyWithVideoLinks = true
    private var _leadTimeSeconds: TimeInterval = 60

    var autoStartEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _enabled
    }

    var autoStartOnlyWithVideoLinks: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _onlyWithVideoLinks
    }

    var autoStartLeadTimeSeconds: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return _leadTimeSeconds
    }

    func setEnabled(_ enabled: Bool) {
        lock.lock()
        _enabled = enabled
        lock.unlock()
    }

    func setOnlyWithVideoLinks(_ only: Bool) {
        lock.lock()
        _onlyWithVideoLinks = only
        lock.unlock()
    }

    func setLeadTimeSeconds(_ seconds: TimeInterval) {
        lock.lock()
        _leadTimeSeconds = seconds
        lock.unlock()
    }
}

// MARK: - Test Helpers

private func makeEvent(
    id: String = "evt-1",
    title: String = "Team Standup",
    startDate: Date,
    endDate: Date? = nil,
    meetingLink: String? = "https://meet.google.com/abc",
    status: String = "confirmed",
    googleEventId: String? = "g-1"
) -> UnifiedCalendarEvent {
    UnifiedCalendarEvent(
        id: id,
        title: title,
        startDate: startDate,
        endDate: endDate ?? startDate.addingTimeInterval(1800),
        location: nil,
        isAllDay: false,
        meetingLink: meetingLink,
        attendees: [],
        source: .google,
        googleEventId: googleEventId,
        calendarId: "primary"
    )
}

// MARK: - Tests

@Suite("MeetingAutoStartService Tests")
struct MeetingAutoStartServiceTests {

    @Test("Auto-start triggers recording at configured time before meeting")
    func testAutoStartTriggersAtLeadTime() async throws {
        let mockStarter = MockMeetingStarter()
        let mockNotifier = MockAutoStartNotifier()
        let mockSettings = MockAutoStartSettings()
        mockSettings.setLeadTimeSeconds(60)

        let now = Date()
        let event = makeEvent(
            title: "Sprint Planning",
            startDate: now.addingTimeInterval(30)
        )

        let service = MeetingAutoStartService(
            meetingStarter: mockStarter,
            notifier: mockNotifier,
            settings: mockSettings,
            now: { now }
        )

        await service.evaluateEvents([event])

        // Wait for the timer/evaluation to trigger
        try await Task.sleep(nanoseconds: 200_000_000)

        let started = await mockStarter.startedTitles
        #expect(started.contains("Sprint Planning"))
    }

    @Test("Auto-start does not trigger if already recording")
    func testAutoStartDoesNotTriggerIfRecording() async throws {
        let mockStarter = MockMeetingStarter()
        await mockStarter.setRecording(true)
        let mockNotifier = MockAutoStartNotifier()
        let mockSettings = MockAutoStartSettings()

        let now = Date()
        let event = makeEvent(
            title: "Daily Standup",
            startDate: now.addingTimeInterval(30)
        )

        let service = MeetingAutoStartService(
            meetingStarter: mockStarter,
            notifier: mockNotifier,
            settings: mockSettings,
            now: { now }
        )

        await service.evaluateEvents([event])
        try await Task.sleep(nanoseconds: 200_000_000)

        let started = await mockStarter.startedTitles
        #expect(started.isEmpty)
    }

    @Test("Auto-start does not trigger if disabled in settings")
    func testAutoStartDoesNotTriggerWhenDisabled() async throws {
        let mockStarter = MockMeetingStarter()
        let mockNotifier = MockAutoStartNotifier()
        let mockSettings = MockAutoStartSettings()
        mockSettings.setEnabled(false)

        let now = Date()
        let event = makeEvent(
            title: "Retro",
            startDate: now.addingTimeInterval(30)
        )

        let service = MeetingAutoStartService(
            meetingStarter: mockStarter,
            notifier: mockNotifier,
            settings: mockSettings,
            now: { now }
        )

        await service.evaluateEvents([event])
        try await Task.sleep(nanoseconds: 200_000_000)

        let started = await mockStarter.startedTitles
        #expect(started.isEmpty)
    }

    @Test("Auto-start sets meeting title from calendar event title")
    func testAutoStartSetsMeetingTitle() async throws {
        let mockStarter = MockMeetingStarter()
        let mockNotifier = MockAutoStartNotifier()
        let mockSettings = MockAutoStartSettings()

        let now = Date()
        let event = makeEvent(
            title: "Architecture Review",
            startDate: now.addingTimeInterval(30)
        )

        let service = MeetingAutoStartService(
            meetingStarter: mockStarter,
            notifier: mockNotifier,
            settings: mockSettings,
            now: { now }
        )

        await service.evaluateEvents([event])
        try await Task.sleep(nanoseconds: 200_000_000)

        let started = await mockStarter.startedTitles
        #expect(started == ["Architecture Review"])
    }

    @Test("Auto-start notification appears before recording starts")
    func testNotificationAppearsBeforeRecording() async throws {
        let mockStarter = MockMeetingStarter()
        let mockNotifier = MockAutoStartNotifier()
        let mockSettings = MockAutoStartSettings()

        let now = Date()
        let event = makeEvent(
            title: "Design Review",
            startDate: now.addingTimeInterval(30)
        )

        let service = MeetingAutoStartService(
            meetingStarter: mockStarter,
            notifier: mockNotifier,
            settings: mockSettings,
            now: { now }
        )

        await service.evaluateEvents([event])
        try await Task.sleep(nanoseconds: 200_000_000)

        let notified = await mockNotifier.notifiedTitles
        #expect(notified.contains("Design Review"))
    }

    @Test("User can dismiss auto-start notification to skip")
    func testUserCanSkipViaNotification() async throws {
        let mockStarter = MockMeetingStarter()
        let mockNotifier = MockAutoStartNotifier()
        await mockNotifier.setShouldSkip(true)
        let mockSettings = MockAutoStartSettings()

        let now = Date()
        let event = makeEvent(
            title: "Skippable Meeting",
            startDate: now.addingTimeInterval(30)
        )

        let service = MeetingAutoStartService(
            meetingStarter: mockStarter,
            notifier: mockNotifier,
            settings: mockSettings,
            now: { now }
        )

        await service.evaluateEvents([event])
        try await Task.sleep(nanoseconds: 200_000_000)

        let started = await mockStarter.startedTitles
        #expect(started.isEmpty)

        let notified = await mockNotifier.notifiedTitles
        #expect(notified.contains("Skippable Meeting"))
    }

    @Test("Cancelled/declined meetings do not trigger auto-start")
    func testCancelledMeetingsDoNotTrigger() async throws {
        let mockStarter = MockMeetingStarter()
        let mockNotifier = MockAutoStartNotifier()
        let mockSettings = MockAutoStartSettings()
        mockSettings.setOnlyWithVideoLinks(false)

        let now = Date()
        // Event with no meeting link and onlyWithVideoLinks = true means no trigger
        // But here we test with a past-end event (cancelled effectively)
        let pastEvent = makeEvent(
            title: "Cancelled Meeting",
            startDate: now.addingTimeInterval(-3600),
            endDate: now.addingTimeInterval(-1800),
            meetingLink: "https://meet.google.com/xyz"
        )

        let service = MeetingAutoStartService(
            meetingStarter: mockStarter,
            notifier: mockNotifier,
            settings: mockSettings,
            now: { now }
        )

        await service.evaluateEvents([pastEvent])
        try await Task.sleep(nanoseconds: 200_000_000)

        let started = await mockStarter.startedTitles
        #expect(started.isEmpty)
    }

    @Test("Events without meeting links are skipped when onlyWithVideoLinks is enabled")
    func testNoMeetingLinkSkippedWhenOnlyVideoLinks() async throws {
        let mockStarter = MockMeetingStarter()
        let mockNotifier = MockAutoStartNotifier()
        let mockSettings = MockAutoStartSettings()
        mockSettings.setOnlyWithVideoLinks(true)

        let now = Date()
        let event = makeEvent(
            title: "No Link Meeting",
            startDate: now.addingTimeInterval(30),
            meetingLink: nil
        )

        let service = MeetingAutoStartService(
            meetingStarter: mockStarter,
            notifier: mockNotifier,
            settings: mockSettings,
            now: { now }
        )

        await service.evaluateEvents([event])
        try await Task.sleep(nanoseconds: 200_000_000)

        let started = await mockStarter.startedTitles
        #expect(started.isEmpty)
    }
}
