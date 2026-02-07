import Testing
import Foundation
@testable import Gophy

@Suite("PlaybackSessionController Tests")
struct PlaybackSessionControllerTests {

    private func makeController() -> (
        controller: PlaybackSessionController,
        playbackService: MockRecordingPlaybackService,
        transcriptionPipeline: MockTranscriptionPipelineForPlayback,
        meetingRepository: MockMeetingRepositoryForPlayback,
        embeddingPipeline: MockEmbeddingPipelineForPlayback
    ) {
        let playbackService = MockRecordingPlaybackService()
        let transcriptionPipeline = MockTranscriptionPipelineForPlayback()
        let meetingRepository = MockMeetingRepositoryForPlayback()
        let embeddingPipeline = MockEmbeddingPipelineForPlayback()

        let controller = PlaybackSessionController(
            playbackService: playbackService,
            transcriptionPipeline: transcriptionPipeline,
            meetingRepository: meetingRepository,
            embeddingPipeline: embeddingPipeline
        )

        return (controller, playbackService, transcriptionPipeline, meetingRepository, embeddingPipeline)
    }

    @Test("Start playback creates meeting record with playback mode")
    func startPlaybackCreatesMeetingRecordWithPlaybackMode() async throws {
        let (controller, _, _, meetingRepository, _) = makeController()
        let testFileURL = URL(fileURLWithPath: "/tmp/test-recording.m4a")

        try await controller.startPlayback(fileURL: testFileURL, title: "Playback Test")

        let createdMeetings = await meetingRepository.createdMeetings
        #expect(createdMeetings.count == 1)
        let meeting = createdMeetings.first!
        #expect(meeting.title == "Playback Test")
        #expect(meeting.status == "active")
        #expect(meeting.mode == "playback")
        #expect(meeting.endedAt == nil)
    }

    @Test("Start playback loads file in playback service")
    func startPlaybackLoadsFileInPlaybackService() async throws {
        let (controller, playbackService, _, _, _) = makeController()
        let testFileURL = URL(fileURLWithPath: "/tmp/test-recording.m4a")

        try await controller.startPlayback(fileURL: testFileURL, title: "Playback Test")

        let loadedFile = await playbackService.loadedFileURL
        #expect(loadedFile == testFileURL)
    }

    @Test("Start playback begins playback")
    func startPlaybackBeginsPlayback() async throws {
        let (controller, playbackService, _, _, _) = makeController()
        let testFileURL = URL(fileURLWithPath: "/tmp/test-recording.m4a")

        try await controller.startPlayback(fileURL: testFileURL, title: "Playback Test")

        let isPlaying = await playbackService.isPlaying
        #expect(isPlaying)
    }

    @Test("Transcript segments from pipeline are persisted in real time")
    func transcriptSegmentsFromPipelineArePersistedInRealTime() async throws {
        let (controller, _, transcriptionPipeline, meetingRepository, _) = makeController()
        let testFileURL = URL(fileURLWithPath: "/tmp/test-recording.m4a")

        let segment = TranscriptSegment(
            text: "Playback transcription",
            startTime: 0.0,
            endTime: 1.0,
            speaker: "Speaker"
        )
        await transcriptionPipeline.setSegments([segment])

        try await controller.startPlayback(fileURL: testFileURL, title: "Playback Test")

        // Give time for async persistence
        try await Task.sleep(nanoseconds: 100_000_000)

        let addedSegments = await meetingRepository.addedSegments
        #expect(addedSegments.count == 1)
        let savedSegment = addedSegments.first!
        #expect(savedSegment.text == "Playback transcription")
        #expect(savedSegment.speaker == "Speaker")
    }

    @Test("Transcript segments appear in event stream")
    func transcriptSegmentsAppearInEventStream() async throws {
        let (controller, _, transcriptionPipeline, _, _) = makeController()
        let testFileURL = URL(fileURLWithPath: "/tmp/test-recording.m4a")

        let segment = TranscriptSegment(
            text: "Event stream test",
            startTime: 0.0,
            endTime: 1.0,
            speaker: "Speaker"
        )
        await transcriptionPipeline.setSegments([segment])

        try await confirmation("Received transcript segment event") { confirm in
            Task { @Sendable in
                try await controller.startPlayback(fileURL: testFileURL, title: "Event Test")
            }

            for await event in controller.eventStream {
                if case .transcriptSegment(let receivedSegment) = event {
                    #expect(receivedSegment.text == "Event stream test")
                    #expect(receivedSegment.speaker == "Speaker")
                    confirm()
                    break
                }
            }
        }
    }

    @Test("Stop playback sets endedAt and completed status")
    func stopPlaybackSetsEndedAtAndCompletedStatus() async throws {
        let (controller, _, _, meetingRepository, _) = makeController()
        let testFileURL = URL(fileURLWithPath: "/tmp/test-recording.m4a")

        try await controller.startPlayback(fileURL: testFileURL, title: "Playback Test")
        let createdMeetings = await meetingRepository.createdMeetings
        let meetingId = createdMeetings.first!.id

        try await controller.stopPlayback()

        let updatedMeetings = await meetingRepository.updatedMeetings
        #expect(updatedMeetings.count == 1)
        let updatedMeeting = updatedMeetings.first!
        #expect(updatedMeeting.id == meetingId)
        #expect(updatedMeeting.status == "completed")
        #expect(updatedMeeting.endedAt != nil)
    }

    @Test("Stop playback indexes meeting")
    func stopPlaybackIndexesMeeting() async throws {
        let (controller, _, _, meetingRepository, embeddingPipeline) = makeController()
        let testFileURL = URL(fileURLWithPath: "/tmp/test-recording.m4a")

        try await controller.startPlayback(fileURL: testFileURL, title: "Playback Test")
        let createdMeetings = await meetingRepository.createdMeetings
        let meetingId = createdMeetings.first!.id

        try await controller.stopPlayback()

        let indexedIds = await embeddingPipeline.indexedMeetingIds
        #expect(indexedIds == [meetingId])
    }

    @Test("Stop playback stops playback service")
    func stopPlaybackStopsPlaybackService() async throws {
        let (controller, playbackService, _, _, _) = makeController()
        let testFileURL = URL(fileURLWithPath: "/tmp/test-recording.m4a")

        try await controller.startPlayback(fileURL: testFileURL, title: "Playback Test")

        try await controller.stopPlayback()

        let isStopped = await playbackService.isStopped
        #expect(isStopped)
    }

    @Test("Pause halts playback")
    func pauseHaltsPlayback() async throws {
        let (controller, playbackService, _, _, _) = makeController()
        let testFileURL = URL(fileURLWithPath: "/tmp/test-recording.m4a")

        try await controller.startPlayback(fileURL: testFileURL, title: "Playback Test")

        await controller.pause()

        let isPaused = await playbackService.isPaused
        #expect(isPaused)
    }

    @Test("Resume restarts playback")
    func resumeRestartsPlayback() async throws {
        let (controller, playbackService, _, _, _) = makeController()
        let testFileURL = URL(fileURLWithPath: "/tmp/test-recording.m4a")

        try await controller.startPlayback(fileURL: testFileURL, title: "Playback Test")
        await controller.pause()

        try await controller.resume()

        let isPlaying = await playbackService.isPlaying
        #expect(isPlaying)
    }

    @Test("Seek clears buffered transcription and restarts")
    func seekClearsBufferedTranscriptionAndRestarts() async throws {
        let (controller, playbackService, transcriptionPipeline, _, _) = makeController()
        let testFileURL = URL(fileURLWithPath: "/tmp/test-recording.m4a")

        try await controller.startPlayback(fileURL: testFileURL, title: "Playback Test")

        // Simulate some transcription happened
        try await Task.sleep(nanoseconds: 50_000_000)

        try await controller.seek(to: 10.0)

        let seekTime = await playbackService.lastSeekTime
        #expect(seekTime == 10.0)

        let pipelineStops = await transcriptionPipeline.stopCallCount
        #expect(pipelineStops >= 1)
    }

    @Test("Seek restarts transcription pipeline")
    func seekRestartsTranscriptionPipeline() async throws {
        let (controller, _, transcriptionPipeline, _, _) = makeController()
        let testFileURL = URL(fileURLWithPath: "/tmp/test-recording.m4a")

        try await controller.startPlayback(fileURL: testFileURL, title: "Playback Test")

        try await controller.seek(to: 5.0)

        // Allow async pipeline restart to propagate
        try await Task.sleep(nanoseconds: 50_000_000)

        // Pipeline should have been stopped and restarted
        let pipelineStarts = await transcriptionPipeline.startCallCount
        #expect(pipelineStarts >= 2) // Initial start + restart after seek
    }

    @Test("Speed change propagates to playback service")
    func speedChangePropagatestoPlaybackService() async throws {
        let (controller, playbackService, _, _, _) = makeController()
        let testFileURL = URL(fileURLWithPath: "/tmp/test-recording.m4a")

        try await controller.startPlayback(fileURL: testFileURL, title: "Playback Test")

        await controller.setSpeed(1.5)

        let currentSpeed = await playbackService.currentSpeed
        #expect(currentSpeed == 1.5)
    }

    @Test("Playback progress events emitted")
    func playbackProgressEventsEmitted() async throws {
        let (controller, playbackService, _, _, _) = makeController()
        let testFileURL = URL(fileURLWithPath: "/tmp/test-recording.m4a")

        await playbackService.setPlaybackProgress(currentTime: 5.0, duration: 60.0)

        try await confirmation("Received playback progress event") { confirm in
            Task { @Sendable in
                try await controller.startPlayback(fileURL: testFileURL, title: "Progress Test")
            }

            for await event in controller.eventStream {
                if case .playbackProgress(let currentTime, let duration) = event {
                    #expect(currentTime == 5.0)
                    #expect(duration == 60.0)
                    confirm()
                    break
                }
            }
        }
    }

    @Test("Status change events emitted")
    func statusChangeEventsEmitted() async throws {
        let (controller, _, _, _, _) = makeController()
        let testFileURL = URL(fileURLWithPath: "/tmp/test-recording.m4a")

        try await confirmation("Received status change events", expectedCount: 2) { confirm in
            Task { @Sendable in
                try await controller.startPlayback(fileURL: testFileURL, title: "Status Test")
            }

            var statuses: [MeetingStatus] = []
            for await event in controller.eventStream {
                if case .statusChange(let status) = event {
                    statuses.append(status)
                    confirm()
                    if statuses.count >= 2 {
                        break
                    }
                }
            }

            #expect(statuses.contains(MeetingStatus.starting))
            #expect(statuses.contains(MeetingStatus.active))
        }
    }
}

// MARK: - Mock RecordingPlaybackService

actor MockRecordingPlaybackService: RecordingPlaybackProtocol {
    var loadedFileURL: URL?
    private var _isPlaying = false
    private var _isPaused = false
    private var _isStopped = false
    private var _currentSpeed: Float = 1.0
    var lastSeekTime: TimeInterval?
    private var mockCurrentTime: TimeInterval = 0.0
    private var mockDuration: TimeInterval = 60.0

    var isPlaying: Bool {
        get async { _isPlaying }
    }

    var isPaused: Bool {
        get async { _isPaused }
    }

    var isStopped: Bool {
        get async { _isStopped }
    }

    var currentSpeed: Float {
        get async { _currentSpeed }
    }

    var state: PlaybackState {
        if _isPlaying { return .playing }
        if _isPaused { return .paused }
        if _isStopped { return .stopped }
        return .idle
    }

    var currentTime: TimeInterval {
        mockCurrentTime
    }

    var duration: TimeInterval {
        mockDuration
    }

    var speed: Float {
        _currentSpeed
    }

    func loadFile(url: URL) async throws {
        loadedFileURL = url
    }

    func play() async throws -> AsyncStream<AudioChunk> {
        _isPlaying = true
        _isPaused = false
        _isStopped = false
        return AsyncStream { _ in }
    }

    func pause() async {
        _isPaused = true
        _isPlaying = false
    }

    func resume() async throws {
        _isPlaying = true
        _isPaused = false
    }

    func stop() async {
        _isStopped = true
        _isPlaying = false
        _isPaused = false
    }

    func seek(to time: TimeInterval) async throws {
        lastSeekTime = time
        mockCurrentTime = time
    }

    func setSpeed(_ rate: Float) async {
        _currentSpeed = rate
    }

    func setPlaybackProgress(currentTime: TimeInterval, duration: TimeInterval) {
        mockCurrentTime = currentTime
        mockDuration = duration
    }
}

// MARK: - Mock TranscriptionPipeline

actor MockTranscriptionPipelineForPlayback: TranscriptionPipelineProtocol {
    private var segmentsToYield: [TranscriptSegment] = []
    var lastLanguageHint: String?
    var stopCallCount = 0
    var startCallCount = 0

    nonisolated func start(mixedStream: AsyncStream<LabeledAudioChunk>) -> AsyncStream<TranscriptSegment> {
        let capturedSelf = self
        return AsyncStream { continuation in
            Task { @Sendable in
                await capturedSelf.incrementStartCount()
                let segments = await capturedSelf.getSegments()
                for segment in segments {
                    continuation.yield(segment)
                }
                continuation.finish()
            }
        }
    }

    func stop() async {
        stopCallCount += 1
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

    private func incrementStartCount() {
        startCallCount += 1
    }
}

// MARK: - Mock MeetingRepository

actor MockMeetingRepositoryForPlayback: MeetingRepositoryProtocol {
    var createdMeetings: [MeetingRecord] = []
    var updatedMeetings: [MeetingRecord] = []
    var addedSegments: [TranscriptSegmentRecord] = []

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
        []
    }
}

// MARK: - Mock EmbeddingPipeline

actor MockEmbeddingPipelineForPlayback: EmbeddingPipelineProtocol {
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
