import XCTest
@testable import Gophy

final class MeetingSessionControllerTests: XCTestCase {
    private var controller: MeetingSessionController!
    private var mockModeController: MockModeController!
    private var mockTranscriptionPipeline: MockTranscriptionPipeline!
    private var mockMeetingRepository: MockMeetingRepository!
    private var mockEmbeddingPipeline: MockEmbeddingPipeline!
    private var mockMicrophoneCapture: MockMicrophoneCaptureForMeeting!
    private var mockSystemAudioCapture: MockSystemAudioCaptureForMeeting!
    override func setUp() async throws {
        try await super.setUp()

        mockModeController = MockModeController()
        mockTranscriptionPipeline = MockTranscriptionPipeline()
        mockMeetingRepository = MockMeetingRepository()
        mockEmbeddingPipeline = MockEmbeddingPipeline()
        mockMicrophoneCapture = MockMicrophoneCaptureForMeeting()
        mockSystemAudioCapture = MockSystemAudioCaptureForMeeting()

        controller = MeetingSessionController(
            modeController: mockModeController,
            transcriptionPipeline: mockTranscriptionPipeline,
            meetingRepository: mockMeetingRepository,
            embeddingPipeline: mockEmbeddingPipeline,
            microphoneCapture: mockMicrophoneCapture,
            systemAudioCapture: mockSystemAudioCapture
        )
    }

    func testStartCreatesMeetingRecordWithActiveStatus() async throws {
        try await controller.start(title: "Test Meeting")

        let createdMeetings = await mockMeetingRepository.createdMeetings
        XCTAssertEqual(createdMeetings.count, 1)
        let meeting = createdMeetings.first!
        XCTAssertEqual(meeting.title, "Test Meeting")
        XCTAssertEqual(meeting.status, "active")
        XCTAssertEqual(meeting.mode, "meeting")
        XCTAssertNil(meeting.endedAt)
    }

    func testStartSwitchesToMeetingMode() async throws {
        try await controller.start(title: "Test Meeting")

        let modes = await mockModeController.switchedModes
        XCTAssertEqual(modes, [.meeting])
    }

    func testStartBeginsAudioCapture() async throws {
        try await controller.start(title: "Test Meeting")

        // Give a moment for the async tasks to execute
        try await Task.sleep(nanoseconds: 10_000_000)

        let micStarted = await mockMicrophoneCapture.isStarted
        let sysStarted = await mockSystemAudioCapture.isStarted
        XCTAssertTrue(micStarted)
        XCTAssertTrue(sysStarted)
    }

    func testTranscriptSegmentsAppearInEventStream() async throws {
        let expectation = expectation(description: "Received transcript segment event")

        let segment = TranscriptSegment(
            text: "Hello world",
            startTime: 0.0,
            endTime: 1.0,
            speaker: "You"
        )
        await mockTranscriptionPipeline.setSegments([segment])

        let localController = controller!

        Task { @Sendable in
            try await localController.start(title: "Test Meeting")
        }

        Task { @Sendable in
            for await event in localController.eventStream {
                if case .transcriptSegment(let receivedSegment) = event {
                    XCTAssertEqual(receivedSegment.text, "Hello world")
                    XCTAssertEqual(receivedSegment.speaker, "You")
                    expectation.fulfill()
                    break
                }
            }
        }

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testSegmentsArePersistedInRealTime() async throws {
        let segment = TranscriptSegment(
            text: "Persistent text",
            startTime: 0.0,
            endTime: 1.0,
            speaker: "Others"
        )
        await mockTranscriptionPipeline.setSegments([segment])

        try await controller.start(title: "Test Meeting")

        // Give time for async persistence
        try await Task.sleep(nanoseconds: 100_000_000)

        let addedSegments = await mockMeetingRepository.addedSegments
        XCTAssertEqual(addedSegments.count, 1)
        let savedSegment = addedSegments.first!
        XCTAssertEqual(savedSegment.text, "Persistent text")
        XCTAssertEqual(savedSegment.speaker, "Others")
    }

    func testStopSetsEndedAtAndCompletedStatus() async throws {
        try await controller.start(title: "Test Meeting")
        let createdMeetings = await mockMeetingRepository.createdMeetings
        let meetingId = createdMeetings.first!.id

        try await controller.stop()

        let updatedMeetings = await mockMeetingRepository.updatedMeetings
        XCTAssertEqual(updatedMeetings.count, 1)
        let updatedMeeting = updatedMeetings.first!
        XCTAssertEqual(updatedMeeting.id, meetingId)
        XCTAssertEqual(updatedMeeting.status, "completed")
        XCTAssertNotNil(updatedMeeting.endedAt)
    }

    func testStopCallsEmbeddingPipelineToIndexMeeting() async throws {
        try await controller.start(title: "Test Meeting")
        let createdMeetings = await mockMeetingRepository.createdMeetings
        let meetingId = createdMeetings.first!.id

        try await controller.stop()

        let indexedIds = await mockEmbeddingPipeline.indexedMeetingIds
        XCTAssertEqual(indexedIds, [meetingId])
    }

    func testPauseHaltsCapture() async throws {
        try await controller.start(title: "Test Meeting")

        await controller.pause()

        let micStopped = await mockMicrophoneCapture.isStopped
        let sysStopped = await mockSystemAudioCapture.isStopped
        XCTAssertTrue(micStopped)
        XCTAssertTrue(sysStopped)
    }

    func testResumeRestartsCapture() async throws {
        try await controller.start(title: "Test Meeting")
        await controller.pause()

        try await controller.resume()

        let micStarted = await mockMicrophoneCapture.isStarted
        let sysStarted = await mockSystemAudioCapture.isStarted
        XCTAssertTrue(micStarted)
        XCTAssertTrue(sysStarted)
    }

    func testRecoverOrphanedMeetingsMarksThemAsInterrupted() async throws {
        let orphanedMeeting = MeetingRecord(
            id: "orphan1",
            title: "Orphaned Meeting",
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: nil,
            mode: "meeting",
            status: "active",
            createdAt: Date().addingTimeInterval(-3600)
        )

        await mockMeetingRepository.setOrphanedMeetings([orphanedMeeting])

        let recovered = try await controller.recoverOrphanedMeetings()

        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered.first?.id, "orphan1")

        let updatedMeetings = await mockMeetingRepository.updatedMeetings
        XCTAssertEqual(updatedMeetings.count, 1)
        let updated = updatedMeetings.first!
        XCTAssertEqual(updated.status, "interrupted")
        XCTAssertNotNil(updated.endedAt)
    }

    func testStatusChangeEventsEmitted() async throws {
        let expectation = expectation(description: "Received status change events")
        expectation.expectedFulfillmentCount = 2

        actor StatusCollector {
            var statuses: [MeetingStatus] = []
            func append(_ status: MeetingStatus) {
                statuses.append(status)
            }
            func getAll() -> [MeetingStatus] {
                statuses
            }
        }

        let collector = StatusCollector()
        let localController = controller!

        Task { @Sendable in
            try await localController.start(title: "Test Meeting")
        }

        Task { @Sendable in
            for await event in localController.eventStream {
                if case .statusChange(let status) = event {
                    await collector.append(status)
                    expectation.fulfill()
                }
            }
        }

        await fulfillment(of: [expectation], timeout: 2.0)

        let statuses = await collector.getAll()
        XCTAssertTrue(statuses.contains(MeetingStatus.starting))
        XCTAssertTrue(statuses.contains(MeetingStatus.active))
    }
}

// MARK: - Mock ModeController

actor MockModeController: ModeControllerProtocol {
    var switchedModes: [Mode] = []

    func switchMode(_ mode: Mode) async throws {
        switchedModes.append(mode)
    }
}

// MARK: - Mock TranscriptionPipeline

actor MockTranscriptionPipeline: TranscriptionPipelineProtocol {
    private var segmentsToYield: [TranscriptSegment] = []
    var lastLanguageHint: String?

    nonisolated func start(mixedStream: AsyncStream<LabeledAudioChunk>) -> AsyncStream<TranscriptSegment> {
        let capturedSelf = self
        return AsyncStream { continuation in
            Task { @Sendable in
                let segments = await capturedSelf.getSegments()
                for segment in segments {
                    continuation.yield(segment)
                }
                continuation.finish()
            }
        }
    }

    func stop() async {
        // No-op
    }

    func setLanguageHint(_ hint: String?) {
        lastLanguageHint = hint
    }

    func setSegments(_ segments: [TranscriptSegment]) {
        segmentsToYield = segments
    }

    private func getSegments() -> [TranscriptSegment] {
        segmentsToYield
    }
}

// MARK: - Mock MeetingRepository

actor MockMeetingRepository: MeetingRepositoryProtocol {
    var createdMeetings: [MeetingRecord] = []
    var updatedMeetings: [MeetingRecord] = []
    var addedSegments: [TranscriptSegmentRecord] = []
    var orphanedMeetings: [MeetingRecord] = []

    func create(_ meeting: MeetingRecord) async throws {
        createdMeetings.append(meeting)
    }

    func update(_ meeting: MeetingRecord) async throws {
        updatedMeetings.append(meeting)
    }

    func get(id: String) async throws -> MeetingRecord? {
        createdMeetings.first { $0.id == id }
    }

    func listAll(limit: Int?, offset: Int) async throws -> [MeetingRecord] {
        createdMeetings
    }

    func delete(id: String) async throws {
        // No-op
    }

    func addTranscriptSegment(_ segment: TranscriptSegmentRecord) async throws {
        addedSegments.append(segment)
    }

    func getTranscript(meetingId: String) async throws -> [TranscriptSegmentRecord] {
        addedSegments.filter { $0.meetingId == meetingId }
    }

    func getSegment(id: String) async throws -> TranscriptSegmentRecord? {
        addedSegments.first { $0.id == id }
    }

    func search(query: String) async throws -> [MeetingRecord] {
        []
    }

    func findOrphaned() async throws -> [MeetingRecord] {
        orphanedMeetings
    }

    func setOrphanedMeetings(_ meetings: [MeetingRecord]) {
        orphanedMeetings = meetings
    }
}

// MARK: - Mock EmbeddingPipeline

actor MockEmbeddingPipeline: EmbeddingPipelineProtocol {
    var indexedMeetingIds: [String] = []

    func indexMeeting(meetingId: String) async throws {
        indexedMeetingIds.append(meetingId)
    }

    func indexDocument(documentId: String) async throws {
        // No-op
    }

    func indexTranscriptSegment(segment: TranscriptSegmentRecord) async throws {
        // No-op
    }

    func indexDocumentChunk(chunk: DocumentChunkRecord) async throws {
        // No-op
    }
}

// MARK: - Mock Audio Capture Services

actor MockMicrophoneCaptureForMeeting: MicrophoneCaptureProtocol {
    private var _isStarted = false
    private var _isStopped = false

    var isStarted: Bool {
        get async { _isStarted }
    }

    var isStopped: Bool {
        get async { _isStopped }
    }

    nonisolated func start() -> AsyncStream<AudioChunk> {
        Task {
            await self.setStarted()
        }
        return AsyncStream { _ in }
    }

    func stop() async {
        _isStopped = true
        _isStarted = false
    }

    private func setStarted() {
        _isStarted = true
        _isStopped = false
    }
}

actor MockSystemAudioCaptureForMeeting: SystemAudioCaptureProtocol {
    private var _isStarted = false
    private var _isStopped = false

    var isStarted: Bool {
        get async { _isStarted }
    }

    var isStopped: Bool {
        get async { _isStopped }
    }

    nonisolated func start() -> AsyncStream<AudioChunk> {
        Task {
            await self.setStarted()
        }
        return AsyncStream { _ in }
    }

    func stop() async {
        _isStopped = true
        _isStarted = false
    }

    private func setStarted() {
        _isStarted = true
        _isStopped = false
    }
}

