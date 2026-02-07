import Testing
import Foundation
@testable import Gophy

// MARK: - Mock Summary Generator

actor MockSummaryGenerator: SummaryGeneratorProtocol {
    private var _summaryToReturn: String = "- Key decision: Use microservices\n- Action item: Set up CI/CD"
    private var _shouldThrow = false

    func setSummary(_ summary: String) {
        _summaryToReturn = summary
    }

    func setShouldThrow(_ should: Bool) {
        _shouldThrow = should
    }

    func generateSummary(transcript: String) async throws -> String {
        guard !_shouldThrow else {
            throw SummaryGeneratorError.generationFailed("Mock error")
        }
        return _summaryToReturn
    }
}

// MARK: - Mock CalendarAPI for Writeback

actor MockCalendarAPIForWriteback: GoogleCalendarAPIClientProtocol {
    private var _patchedDescriptions: [(calendarId: String, eventId: String, description: String)] = []
    private var _patchedProperties: [(calendarId: String, eventId: String, properties: [String: String])] = []
    private var _shouldThrowOnPatch = false
    private var _fetchedEvent: CalendarEvent?

    var patchedDescriptions: [(calendarId: String, eventId: String, description: String)] {
        _patchedDescriptions
    }

    var patchedProperties: [(calendarId: String, eventId: String, properties: [String: String])] {
        _patchedProperties
    }

    func setShouldThrowOnPatch(_ should: Bool) {
        _shouldThrowOnPatch = should
    }

    func setFetchedEvent(_ event: CalendarEvent?) {
        _fetchedEvent = event
    }

    func fetchCalendarList() async throws -> [CalendarInfo] {
        [CalendarInfo(id: "primary", summary: "Calendar", primary: true, backgroundColor: nil)]
    }

    func fetchEvents(
        calendarId: String,
        timeMin: Date?,
        timeMax: Date?,
        syncToken: String?,
        pageToken: String?
    ) async throws -> EventListResponse {
        if let event = _fetchedEvent {
            return EventListResponse(items: [event], nextSyncToken: nil, nextPageToken: nil)
        }
        return EventListResponse(items: [], nextSyncToken: nil, nextPageToken: nil)
    }

    func patchEvent(calendarId: String, eventId: String, description: String) async throws {
        guard !_shouldThrowOnPatch else {
            throw CalendarAPIError.serverError(500, "Internal error")
        }
        _patchedDescriptions.append((calendarId: calendarId, eventId: eventId, description: description))
    }

    func patchExtendedProperties(calendarId: String, eventId: String, properties: [String: String]) async throws {
        guard !_shouldThrowOnPatch else {
            throw CalendarAPIError.serverError(500, "Internal error")
        }
        _patchedProperties.append((calendarId: calendarId, eventId: eventId, properties: properties))
    }
}

// MARK: - Mock Auth Service for Writeback

actor MockAuthForWriteback: GoogleAuthServiceProtocol {
    private var _isSignedIn = true

    func setSignedIn(_ signedIn: Bool) {
        _isSignedIn = signedIn
    }

    func freshAccessToken() async throws -> String {
        guard _isSignedIn else {
            throw GoogleAuthError.notSignedIn
        }
        return "mock-token"
    }

    var isSignedIn: Bool {
        _isSignedIn
    }
}

// MARK: - Mock Meeting Repository for Writeback

actor MockMeetingRepoForWriteback: WritebackMeetingRepositoryProtocol {
    private var _meetings: [String: MeetingRecord] = [:]
    private var _transcripts: [String: [TranscriptSegmentRecord]] = [:]

    func addMeeting(_ meeting: MeetingRecord) {
        _meetings[meeting.id] = meeting
    }

    func addTranscript(_ segments: [TranscriptSegmentRecord], for meetingId: String) {
        _transcripts[meetingId] = segments
    }

    func get(id: String) async throws -> MeetingRecord? {
        return _meetings[id]
    }

    func getTranscript(meetingId: String) async throws -> [TranscriptSegmentRecord] {
        return _transcripts[meetingId] ?? []
    }
}

// MARK: - Tests

@Suite("MeetingSummaryWritebackService Tests")
struct MeetingSummaryWritebackServiceTests {

    // MARK: - Helpers

    private func makeMeeting(
        id: String = "meeting-1",
        title: String = "Sprint Planning",
        calendarEventId: String? = "g-event-1",
        calendarId: String? = "primary"
    ) -> MeetingRecord {
        MeetingRecord(
            id: id,
            title: title,
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            mode: "meeting",
            status: "completed",
            createdAt: Date().addingTimeInterval(-3600)
        )
    }

    private func makeSegments(meetingId: String) -> [TranscriptSegmentRecord] {
        [
            TranscriptSegmentRecord(
                id: "seg-1",
                meetingId: meetingId,
                text: "Let's discuss the architecture",
                speaker: "Alice",
                startTime: 0,
                endTime: 5,
                createdAt: Date()
            ),
            TranscriptSegmentRecord(
                id: "seg-2",
                meetingId: meetingId,
                text: "I propose we use microservices",
                speaker: "Bob",
                startTime: 5,
                endTime: 10,
                createdAt: Date()
            ),
        ]
    }

    @Test("Writeback generates summary from transcript and writes to event description")
    func testWritebackGeneratesSummaryAndWritesToDescription() async throws {
        let apiClient = MockCalendarAPIForWriteback()
        let summaryGen = MockSummaryGenerator()
        let authService = MockAuthForWriteback()
        let meetingRepo = MockMeetingRepoForWriteback()

        let meeting = makeMeeting()
        await meetingRepo.addMeeting(meeting)
        await meetingRepo.addTranscript(makeSegments(meetingId: meeting.id), for: meeting.id)

        let service = MeetingSummaryWritebackService(
            apiClient: apiClient,
            summaryGenerator: summaryGen,
            authService: authService,
            meetingRepository: meetingRepo
        )

        try await service.writeBack(
            meetingId: meeting.id,
            calendarEventId: "g-event-1",
            calendarId: "primary",
            existingDescription: nil
        )

        let patches = await apiClient.patchedDescriptions
        #expect(patches.count == 1)
        #expect(patches[0].eventId == "g-event-1")
        #expect(patches[0].description.contains("Meeting Summary (by Gophy)"))
    }

    @Test("Writeback stores summary in extendedProperties.private for Gophy-only data")
    func testWritebackStoresExtendedProperties() async throws {
        let apiClient = MockCalendarAPIForWriteback()
        let summaryGen = MockSummaryGenerator()
        let authService = MockAuthForWriteback()
        let meetingRepo = MockMeetingRepoForWriteback()

        let meeting = makeMeeting()
        await meetingRepo.addMeeting(meeting)
        await meetingRepo.addTranscript(makeSegments(meetingId: meeting.id), for: meeting.id)

        let service = MeetingSummaryWritebackService(
            apiClient: apiClient,
            summaryGenerator: summaryGen,
            authService: authService,
            meetingRepository: meetingRepo
        )

        try await service.writeBack(
            meetingId: meeting.id,
            calendarEventId: "g-event-1",
            calendarId: "primary",
            existingDescription: nil
        )

        let props = await apiClient.patchedProperties
        #expect(props.count == 1)
        #expect(props[0].properties["gophy_meeting_id"] == meeting.id)
        #expect(props[0].properties["gophy_summary"] != nil)
        #expect(props[0].properties["gophy_recorded_at"] != nil)
    }

    @Test("Writeback appends to existing description (does not overwrite)")
    func testWritebackAppendsToExistingDescription() async throws {
        let apiClient = MockCalendarAPIForWriteback()
        let summaryGen = MockSummaryGenerator()
        let authService = MockAuthForWriteback()
        let meetingRepo = MockMeetingRepoForWriteback()

        let meeting = makeMeeting()
        await meetingRepo.addMeeting(meeting)
        await meetingRepo.addTranscript(makeSegments(meetingId: meeting.id), for: meeting.id)

        let service = MeetingSummaryWritebackService(
            apiClient: apiClient,
            summaryGenerator: summaryGen,
            authService: authService,
            meetingRepository: meetingRepo
        )

        try await service.writeBack(
            meetingId: meeting.id,
            calendarEventId: "g-event-1",
            calendarId: "primary",
            existingDescription: "Original meeting agenda"
        )

        let patches = await apiClient.patchedDescriptions
        #expect(patches.count == 1)
        #expect(patches[0].description.hasPrefix("Original meeting agenda"))
        #expect(patches[0].description.contains("---"))
        #expect(patches[0].description.contains("Meeting Summary (by Gophy)"))
    }

    @Test("Writeback skips if no calendarEventId on meeting")
    func testWritebackSkipsWithoutCalendarEventId() async throws {
        let apiClient = MockCalendarAPIForWriteback()
        let summaryGen = MockSummaryGenerator()
        let authService = MockAuthForWriteback()
        let meetingRepo = MockMeetingRepoForWriteback()

        let meeting = makeMeeting(calendarEventId: nil)
        await meetingRepo.addMeeting(meeting)

        let service = MeetingSummaryWritebackService(
            apiClient: apiClient,
            summaryGenerator: summaryGen,
            authService: authService,
            meetingRepository: meetingRepo
        )

        try await service.writeBack(
            meetingId: meeting.id,
            calendarEventId: nil,
            calendarId: nil,
            existingDescription: nil
        )

        let patches = await apiClient.patchedDescriptions
        #expect(patches.isEmpty)
    }

    @Test("Writeback skips if user is not signed in to Google")
    func testWritebackSkipsWhenNotSignedIn() async throws {
        let apiClient = MockCalendarAPIForWriteback()
        let summaryGen = MockSummaryGenerator()
        let authService = MockAuthForWriteback()
        await authService.setSignedIn(false)
        let meetingRepo = MockMeetingRepoForWriteback()

        let meeting = makeMeeting()
        await meetingRepo.addMeeting(meeting)
        await meetingRepo.addTranscript(makeSegments(meetingId: meeting.id), for: meeting.id)

        let service = MeetingSummaryWritebackService(
            apiClient: apiClient,
            summaryGenerator: summaryGen,
            authService: authService,
            meetingRepository: meetingRepo
        )

        try await service.writeBack(
            meetingId: meeting.id,
            calendarEventId: "g-event-1",
            calendarId: "primary",
            existingDescription: nil
        )

        let patches = await apiClient.patchedDescriptions
        #expect(patches.isEmpty)
    }

    @Test("Writeback failure does not delete local meeting data")
    func testWritebackFailurePreservesLocalData() async throws {
        let apiClient = MockCalendarAPIForWriteback()
        await apiClient.setShouldThrowOnPatch(true)
        let summaryGen = MockSummaryGenerator()
        let authService = MockAuthForWriteback()
        let meetingRepo = MockMeetingRepoForWriteback()

        let meeting = makeMeeting()
        await meetingRepo.addMeeting(meeting)
        await meetingRepo.addTranscript(makeSegments(meetingId: meeting.id), for: meeting.id)

        let service = MeetingSummaryWritebackService(
            apiClient: apiClient,
            summaryGenerator: summaryGen,
            authService: authService,
            meetingRepository: meetingRepo
        )

        do {
            try await service.writeBack(
                meetingId: meeting.id,
                calendarEventId: "g-event-1",
                calendarId: "primary",
                existingDescription: nil
            )
        } catch {
            // Expected to fail
        }

        // Verify meeting still exists
        let storedMeeting = try await meetingRepo.get(id: meeting.id)
        #expect(storedMeeting != nil)
        #expect(storedMeeting?.title == "Sprint Planning")
    }

    @Test("Manual trigger generates and writes back summary on demand")
    func testManualTriggerWritesBack() async throws {
        let apiClient = MockCalendarAPIForWriteback()
        let summaryGen = MockSummaryGenerator()
        await summaryGen.setSummary("Manual summary bullet point")
        let authService = MockAuthForWriteback()
        let meetingRepo = MockMeetingRepoForWriteback()

        let meeting = makeMeeting()
        await meetingRepo.addMeeting(meeting)
        await meetingRepo.addTranscript(makeSegments(meetingId: meeting.id), for: meeting.id)

        let service = MeetingSummaryWritebackService(
            apiClient: apiClient,
            summaryGenerator: summaryGen,
            authService: authService,
            meetingRepository: meetingRepo
        )

        try await service.writeBack(
            meetingId: meeting.id,
            calendarEventId: "g-event-1",
            calendarId: "primary",
            existingDescription: nil
        )

        let patches = await apiClient.patchedDescriptions
        #expect(patches.count == 1)
        #expect(patches[0].description.contains("Manual summary bullet point"))
    }
}
