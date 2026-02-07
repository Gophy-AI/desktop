import Testing
import Foundation
import GRDB
@testable import Gophy

// MARK: - Integration Mocks

/// Mock playback service that yields controllable audio chunks
private actor IntegrationMockPlaybackService: RecordingPlaybackProtocol {
    var loadedFileURL: URL?
    private var _state: PlaybackState = .idle
    private var _currentTime: TimeInterval = 0.0
    private var _duration: TimeInterval = 30.0
    private var _speed: Float = 1.0
    private var chunkContinuation: AsyncStream<AudioChunk>.Continuation?
    private var chunksToEmit: [AudioChunk] = []

    var state: PlaybackState { _state }
    var currentTime: TimeInterval { _currentTime }
    var duration: TimeInterval { _duration }
    var speed: Float { _speed }

    func configure(duration: TimeInterval, chunks: [AudioChunk]) {
        _duration = duration
        chunksToEmit = chunks
    }

    func setCurrentTime(_ time: TimeInterval) {
        _currentTime = time
    }

    func loadFile(url: URL) async throws {
        loadedFileURL = url
        _state = .loaded
    }

    func play() async throws -> AsyncStream<AudioChunk> {
        guard _state == .loaded || _state == .stopped else {
            throw RecordingPlaybackError.alreadyPlaying
        }
        _state = .playing

        let chunks = chunksToEmit
        var streamContinuation: AsyncStream<AudioChunk>.Continuation!
        let stream = AsyncStream<AudioChunk> { continuation in
            streamContinuation = continuation
        }
        self.chunkContinuation = streamContinuation

        Task {
            for chunk in chunks {
                streamContinuation.yield(chunk)
            }
            streamContinuation.finish()
        }

        return stream
    }

    func pause() async {
        _state = .paused
    }

    func resume() async throws {
        _state = .playing
    }

    func stop() async {
        chunkContinuation?.finish()
        chunkContinuation = nil
        _state = .stopped
    }

    func seek(to time: TimeInterval) async throws {
        _currentTime = time
        // Seeking while playing: stop and prepare for re-play
        if _state == .playing {
            _state = .loaded
        } else {
            _state = .loaded
        }
    }

    func setSpeed(_ rate: Float) async {
        _speed = rate
    }
}

/// Mock transcription pipeline that produces deterministic segments from labeled audio
private actor IntegrationMockTranscriptionPipeline: TranscriptionPipelineProtocol {
    private var segmentsToYield: [TranscriptSegment] = []
    private var segmentsAfterSeek: [TranscriptSegment] = []
    private var useSeekSegments = false
    var startCallCount = 0
    var stopCallCount = 0

    func setSegments(_ segments: [TranscriptSegment]) {
        segmentsToYield = segments
    }

    func setSegmentsAfterSeek(_ segments: [TranscriptSegment]) {
        segmentsAfterSeek = segments
    }

    func activateSeekSegments() {
        useSeekSegments = true
    }

    nonisolated func start(mixedStream: AsyncStream<LabeledAudioChunk>) -> AsyncStream<TranscriptSegment> {
        let capturedSelf = self
        return AsyncStream { continuation in
            Task { @Sendable in
                await capturedSelf.incrementStartCount()
                let segments = await capturedSelf.getCurrentSegments()
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

    func setLanguageHint(_ hint: String?) async {}

    private func incrementStartCount() { startCallCount += 1 }

    private func getCurrentSegments() -> [TranscriptSegment] {
        if useSeekSegments && !segmentsAfterSeek.isEmpty {
            return segmentsAfterSeek
        }
        return segmentsToYield
    }
}

/// Mock embedding pipeline that records indexed meeting IDs
private actor IntegrationMockEmbeddingPipeline: EmbeddingPipelineProtocol {
    var indexedMeetingIds: [String] = []

    func indexMeeting(meetingId: String) async throws {
        indexedMeetingIds.append(meetingId)
    }

    func indexDocument(documentId: String) async throws {}
    func indexTranscriptSegment(segment: TranscriptSegmentRecord) async throws {}
    func indexDocumentChunk(chunk: DocumentChunkRecord) async throws {}
}

/// Mock meeting repository backed by in-memory arrays for full CRUD
private actor IntegrationMockMeetingRepository: MeetingRepositoryProtocol {
    var meetings: [MeetingRecord] = []
    var segments: [TranscriptSegmentRecord] = []
    var speakerLabels: [SpeakerLabelRecord] = []

    func create(_ meeting: MeetingRecord) async throws {
        meetings.append(meeting)
    }

    func update(_ meeting: MeetingRecord) async throws {
        if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
            meetings[index] = meeting
        }
    }

    func get(id: String) async throws -> MeetingRecord? {
        meetings.first { $0.id == id }
    }

    func listAll(limit: Int?, offset: Int) async throws -> [MeetingRecord] {
        let sorted = meetings.sorted { $0.startedAt > $1.startedAt }
        if let limit = limit {
            return Array(sorted.dropFirst(offset).prefix(limit))
        }
        return Array(sorted.dropFirst(offset))
    }

    func delete(id: String) async throws {
        meetings.removeAll { $0.id == id }
        segments.removeAll { $0.meetingId == id }
        speakerLabels.removeAll { $0.meetingId == id }
    }

    func addTranscriptSegment(_ segment: TranscriptSegmentRecord) async throws {
        segments.append(segment)
    }

    func getTranscript(meetingId: String) async throws -> [TranscriptSegmentRecord] {
        segments.filter { $0.meetingId == meetingId }
            .sorted { $0.startTime < $1.startTime }
    }

    func getSegment(id: String) async throws -> TranscriptSegmentRecord? {
        segments.first { $0.id == id }
    }

    func search(query: String) async throws -> [MeetingRecord] {
        let matchingSegments = segments.filter { $0.text.localizedCaseInsensitiveContains(query) }
        let matchingMeetingIds = Set(matchingSegments.map { $0.meetingId })
        return meetings.filter { matchingMeetingIds.contains($0.id) }
    }

    func findOrphaned() async throws -> [MeetingRecord] {
        meetings.filter { $0.status == "active" && $0.endedAt == nil }
    }

    func getSpeakerLabels(meetingId: String) async throws -> [SpeakerLabelRecord] {
        speakerLabels.filter { $0.meetingId == meetingId }
            .sorted { $0.originalLabel < $1.originalLabel }
    }

    func upsertSpeakerLabel(_ label: SpeakerLabelRecord) async throws {
        if let index = speakerLabels.firstIndex(where: { $0.id == label.id }) {
            speakerLabels[index] = label
        } else {
            speakerLabels.append(label)
        }
    }
}

// MARK: - Integration Test Suite

@Suite("Recording Playback Integration Tests")
struct RecordingPlaybackIntegrationTests {

    // MARK: - Helpers

    private func makeTestChunks(count: Int, samplesPerChunk: Int = 16000) -> [AudioChunk] {
        (0..<count).map { i in
            AudioChunk(
                samples: [Float](repeating: 0.1 * Float(i + 1), count: samplesPerChunk),
                timestamp: TimeInterval(i),
                source: .systemAudio
            )
        }
    }

    private func makeController(
        chunks: [AudioChunk] = [],
        duration: TimeInterval = 30.0,
        segments: [TranscriptSegment] = []
    ) async -> (
        controller: PlaybackSessionController,
        playbackService: IntegrationMockPlaybackService,
        transcriptionPipeline: IntegrationMockTranscriptionPipeline,
        meetingRepository: IntegrationMockMeetingRepository,
        embeddingPipeline: IntegrationMockEmbeddingPipeline
    ) {
        let playbackService = IntegrationMockPlaybackService()
        let transcriptionPipeline = IntegrationMockTranscriptionPipeline()
        let meetingRepository = IntegrationMockMeetingRepository()
        let embeddingPipeline = IntegrationMockEmbeddingPipeline()

        await playbackService.configure(duration: duration, chunks: chunks)
        await transcriptionPipeline.setSegments(segments)

        let controller = PlaybackSessionController(
            playbackService: playbackService,
            transcriptionPipeline: transcriptionPipeline,
            meetingRepository: meetingRepository,
            embeddingPipeline: embeddingPipeline
        )

        return (controller, playbackService, transcriptionPipeline, meetingRepository, embeddingPipeline)
    }

    // MARK: - Test 1: Import WAV -> diarize -> playback -> transcription -> segments in DB

    @Test("End-to-end: import file, playback, transcription, segments persisted in DB")
    func importPlaybackTranscriptionPersisted() async throws {
        let segments = [
            TranscriptSegment(text: "Hello from speaker one", startTime: 0.0, endTime: 3.0, speaker: "Speaker 1"),
            TranscriptSegment(text: "Hi there from speaker two", startTime: 3.0, endTime: 6.0, speaker: "Speaker 2"),
            TranscriptSegment(text: "Let us begin the meeting", startTime: 6.0, endTime: 10.0, speaker: "Speaker 1"),
        ]
        let chunks = makeTestChunks(count: 3)

        let (controller, _, _, meetingRepository, embeddingPipeline) = await makeController(
            chunks: chunks,
            duration: 10.0,
            segments: segments
        )

        let testFileURL = URL(fileURLWithPath: "/tmp/test-recording-integration.wav")

        // Start playback
        try await controller.startPlayback(fileURL: testFileURL, title: "Integration Test Meeting")

        // Allow async transcription pipeline to produce segments
        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify meeting record created with mode="playback"
        let meetings = await meetingRepository.meetings
        #expect(meetings.count == 1)
        let meeting = meetings[0]
        #expect(meeting.mode == "playback")
        #expect(meeting.status == "active")
        #expect(meeting.title == "Integration Test Meeting")
        #expect(meeting.sourceFilePath == "/tmp/test-recording-integration.wav")

        // Verify transcript segments persisted in DB
        let persistedSegments = await meetingRepository.segments
        #expect(persistedSegments.count == 3)
        #expect(persistedSegments[0].text == "Hello from speaker one")
        #expect(persistedSegments[0].speaker == "Speaker 1")
        #expect(persistedSegments[1].text == "Hi there from speaker two")
        #expect(persistedSegments[1].speaker == "Speaker 2")
        #expect(persistedSegments[2].text == "Let us begin the meeting")
        #expect(persistedSegments[2].speaker == "Speaker 1")

        // Stop playback
        try await controller.stopPlayback()

        // Verify meeting marked completed
        let updatedMeetings = await meetingRepository.meetings
        let updatedMeeting = updatedMeetings.first { $0.id == meeting.id }
        #expect(updatedMeeting?.status == "completed")
        #expect(updatedMeeting?.endedAt != nil)

        // Verify embedding pipeline indexed the meeting
        let indexedIds = await embeddingPipeline.indexedMeetingIds
        #expect(indexedIds.count == 1)
        #expect(indexedIds[0] == meeting.id)
    }

    // MARK: - Test 2: Import file -> playback at 2x speed -> speed propagated

    @Test("Playback at 2x speed propagates to playback service")
    func playbackAt2xSpeedPropagates() async throws {
        let segments = [
            TranscriptSegment(text: "Fast playback test", startTime: 0.0, endTime: 2.0, speaker: "Speaker 1"),
        ]
        let chunks = makeTestChunks(count: 2)

        let (controller, playbackService, _, meetingRepository, _) = await makeController(
            chunks: chunks,
            duration: 4.0,
            segments: segments
        )

        let testFileURL = URL(fileURLWithPath: "/tmp/test-recording-2x.wav")

        // Start playback
        try await controller.startPlayback(fileURL: testFileURL, title: "2x Speed Test")

        // Set speed to 2x
        await controller.setSpeed(2.0)

        // Verify speed was propagated
        let currentSpeed = await playbackService.speed
        #expect(currentSpeed == 2.0)

        // Allow transcription to complete
        try await Task.sleep(nanoseconds: 150_000_000)

        // Verify segments still arrive correctly
        let persistedSegments = await meetingRepository.segments
        #expect(persistedSegments.count == 1)
        #expect(persistedSegments[0].text == "Fast playback test")

        try await controller.stopPlayback()
    }

    // MARK: - Test 3: Seek during playback -> transcript resumes from new position

    @Test("Seek during playback clears pipeline and restarts transcription")
    func seekDuringPlaybackRestartsTranscription() async throws {
        let initialSegments = [
            TranscriptSegment(text: "Before seek segment", startTime: 0.0, endTime: 3.0, speaker: "Speaker 1"),
        ]
        let afterSeekSegments = [
            TranscriptSegment(text: "After seek segment", startTime: 15.0, endTime: 18.0, speaker: "Speaker 2"),
        ]
        let chunks = makeTestChunks(count: 2)

        let (controller, playbackService, transcriptionPipeline, meetingRepository, _) = await makeController(
            chunks: chunks,
            duration: 30.0,
            segments: initialSegments
        )

        // Configure the pipeline to switch segments after seek
        await transcriptionPipeline.setSegmentsAfterSeek(afterSeekSegments)

        let testFileURL = URL(fileURLWithPath: "/tmp/test-recording-seek.wav")

        // Start playback
        try await controller.startPlayback(fileURL: testFileURL, title: "Seek Test")

        // Wait for initial segments to be processed
        try await Task.sleep(nanoseconds: 150_000_000)

        // Verify initial segment persisted
        var persistedSegments = await meetingRepository.segments
        #expect(persistedSegments.count >= 1)
        #expect(persistedSegments[0].text == "Before seek segment")

        // Activate seek mode in the mock pipeline
        await transcriptionPipeline.activateSeekSegments()

        // Seek to 15 seconds
        try await controller.seek(to: 15.0)

        // Verify seek was forwarded to playback service
        let seekTime = await playbackService.currentTime
        #expect(seekTime == 15.0)

        // Verify transcription pipeline was stopped (for re-start)
        let stopCount = await transcriptionPipeline.stopCallCount
        #expect(stopCount >= 1)

        // Wait for post-seek transcription
        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify post-seek segment arrived
        persistedSegments = await meetingRepository.segments
        let afterSeekPresent = persistedSegments.contains { $0.text == "After seek segment" }
        #expect(afterSeekPresent, "Post-seek segment should be persisted")

        try await controller.stopPlayback()
    }

    // MARK: - Test 4: Playback meeting appears with mode="playback"

    @Test("Playback meeting stored with mode=playback, queryable by mode")
    func playbackMeetingHasCorrectMode() async throws {
        let segments = [
            TranscriptSegment(text: "Mode test", startTime: 0.0, endTime: 1.0, speaker: "Playback"),
        ]
        let chunks = makeTestChunks(count: 1)

        let (controller, _, _, meetingRepository, _) = await makeController(
            chunks: chunks,
            duration: 5.0,
            segments: segments
        )

        let testFileURL = URL(fileURLWithPath: "/tmp/test-recording-mode.wav")

        // Start and complete playback
        try await controller.startPlayback(fileURL: testFileURL, title: "Mode Test Meeting")
        try await Task.sleep(nanoseconds: 100_000_000)
        try await controller.stopPlayback()

        // List all meetings and filter by mode
        let allMeetings = await meetingRepository.meetings
        let playbackMeetings = allMeetings.filter { $0.mode == "playback" }
        let liveMeetings = allMeetings.filter { $0.mode == "meeting" }

        #expect(playbackMeetings.count == 1)
        #expect(liveMeetings.count == 0)

        let playbackMeeting = playbackMeetings[0]
        #expect(playbackMeeting.title == "Mode Test Meeting")
        #expect(playbackMeeting.status == "completed")
        #expect(playbackMeeting.endedAt != nil)
        #expect(playbackMeeting.sourceFilePath == "/tmp/test-recording-mode.wav")
    }

    // MARK: - Test 5: Re-opening completed playback meeting shows full transcript

    @Test("Re-opening completed playback meeting retrieves full transcript from DB")
    func reOpenCompletedPlaybackMeetingShowsFullTranscript() async throws {
        let segments = [
            TranscriptSegment(text: "First segment of completed meeting", startTime: 0.0, endTime: 5.0, speaker: "Speaker 1"),
            TranscriptSegment(text: "Second segment of completed meeting", startTime: 5.0, endTime: 10.0, speaker: "Speaker 2"),
            TranscriptSegment(text: "Third segment wrapping up", startTime: 10.0, endTime: 15.0, speaker: "Speaker 1"),
        ]
        let chunks = makeTestChunks(count: 3)

        let (controller, _, _, meetingRepository, _) = await makeController(
            chunks: chunks,
            duration: 15.0,
            segments: segments
        )

        let testFileURL = URL(fileURLWithPath: "/tmp/test-recording-reopen.wav")

        // Complete a full playback session
        try await controller.startPlayback(fileURL: testFileURL, title: "Completed Meeting")
        try await Task.sleep(nanoseconds: 200_000_000)
        try await controller.stopPlayback()

        // Verify meeting is completed
        let allMeetings = await meetingRepository.meetings
        #expect(allMeetings.count == 1)
        let meetingId = allMeetings[0].id
        #expect(allMeetings[0].status == "completed")

        // Simulate "re-opening" by querying the transcript from repository
        let transcript = try await meetingRepository.getTranscript(meetingId: meetingId)

        #expect(transcript.count == 3)
        #expect(transcript[0].text == "First segment of completed meeting")
        #expect(transcript[0].speaker == "Speaker 1")
        #expect(transcript[0].startTime == 0.0)

        #expect(transcript[1].text == "Second segment of completed meeting")
        #expect(transcript[1].speaker == "Speaker 2")
        #expect(transcript[1].startTime == 5.0)

        #expect(transcript[2].text == "Third segment wrapping up")
        #expect(transcript[2].speaker == "Speaker 1")
        #expect(transcript[2].startTime == 10.0)

        // Verify meeting can be fetched by ID
        let fetchedMeeting = try await meetingRepository.get(id: meetingId)
        #expect(fetchedMeeting != nil)
        #expect(fetchedMeeting?.title == "Completed Meeting")
        #expect(fetchedMeeting?.mode == "playback")
    }

    // MARK: - Test 6: Speaker labels persist across sessions

    @Test("Speaker labels persist across sessions via repository")
    func speakerLabelsPersistAcrossSessions() async throws {
        let segments = [
            TranscriptSegment(text: "Speaker one talking", startTime: 0.0, endTime: 3.0, speaker: "Speaker 1"),
            TranscriptSegment(text: "Speaker two talking", startTime: 3.0, endTime: 6.0, speaker: "Speaker 2"),
        ]
        let chunks = makeTestChunks(count: 2)

        let (controller, _, _, meetingRepository, _) = await makeController(
            chunks: chunks,
            duration: 6.0,
            segments: segments
        )

        let testFileURL = URL(fileURLWithPath: "/tmp/test-recording-speakers.wav")

        // Start playback and complete it
        try await controller.startPlayback(fileURL: testFileURL, title: "Speaker Label Test")
        try await Task.sleep(nanoseconds: 150_000_000)
        try await controller.stopPlayback()

        let allMeetings = await meetingRepository.meetings
        let meetingId = allMeetings[0].id

        // Simulate user renaming speakers by saving speaker labels
        let label1 = SpeakerLabelRecord(
            id: UUID().uuidString,
            meetingId: meetingId,
            originalLabel: "Speaker 1",
            customLabel: "Alice",
            color: "#3B82F6",
            createdAt: Date()
        )
        let label2 = SpeakerLabelRecord(
            id: UUID().uuidString,
            meetingId: meetingId,
            originalLabel: "Speaker 2",
            customLabel: "Bob",
            color: "#10B981",
            createdAt: Date()
        )

        try await meetingRepository.upsertSpeakerLabel(label1)
        try await meetingRepository.upsertSpeakerLabel(label2)

        // Simulate closing and re-opening: retrieve speaker labels from repository
        let retrievedLabels = try await meetingRepository.getSpeakerLabels(meetingId: meetingId)

        #expect(retrievedLabels.count == 2)

        let aliceLabel = retrievedLabels.first { $0.originalLabel == "Speaker 1" }
        #expect(aliceLabel != nil)
        #expect(aliceLabel?.customLabel == "Alice")
        #expect(aliceLabel?.color == "#3B82F6")

        let bobLabel = retrievedLabels.first { $0.originalLabel == "Speaker 2" }
        #expect(bobLabel != nil)
        #expect(bobLabel?.customLabel == "Bob")
        #expect(bobLabel?.color == "#10B981")

        // Verify updating an existing label (rename again)
        let updatedLabel = SpeakerLabelRecord(
            id: aliceLabel!.id,
            meetingId: meetingId,
            originalLabel: "Speaker 1",
            customLabel: "Alice Smith",
            color: "#3B82F6",
            createdAt: aliceLabel!.createdAt
        )
        try await meetingRepository.upsertSpeakerLabel(updatedLabel)

        let updatedLabels = try await meetingRepository.getSpeakerLabels(meetingId: meetingId)
        let renamedAlice = updatedLabels.first { $0.originalLabel == "Speaker 1" }
        #expect(renamedAlice?.customLabel == "Alice Smith")
    }

    // MARK: - Test 7: Event stream emits transcript segments and status changes

    @Test("Event stream emits status changes and transcript segments during playback")
    func eventStreamEmitsStatusAndTranscripts() async throws {
        let segments = [
            TranscriptSegment(text: "Event stream test", startTime: 0.0, endTime: 2.0, speaker: "Speaker 1"),
        ]
        let chunks = makeTestChunks(count: 1)

        let (controller, _, _, _, _) = await makeController(
            chunks: chunks,
            duration: 5.0,
            segments: segments
        )

        let testFileURL = URL(fileURLWithPath: "/tmp/test-recording-events.wav")

        try await confirmation("Received expected events", expectedCount: 3) { confirm in
            Task { @Sendable in
                try await controller.startPlayback(fileURL: testFileURL, title: "Event Stream Test")
            }

            var receivedStatuses: [MeetingStatus] = []
            var receivedTranscriptCount = 0

            for await event in controller.eventStream {
                switch event {
                case .statusChange(let status):
                    receivedStatuses.append(status)
                    confirm()
                case .transcriptSegment(let segment):
                    #expect(segment.text == "Event stream test")
                    receivedTranscriptCount += 1
                    confirm()
                default:
                    break
                }

                // We expect: .starting, .active, and one transcript segment
                if receivedStatuses.count >= 2 && receivedTranscriptCount >= 1 {
                    break
                }
            }

            #expect(receivedStatuses.contains(.starting))
            #expect(receivedStatuses.contains(.active))
            #expect(receivedTranscriptCount == 1)
        }
    }

    // MARK: - Test 8: Pause and resume maintain session state

    @Test("Pause and resume maintain session state correctly")
    func pauseResumeMaintenanceSessionState() async throws {
        let segments = [
            TranscriptSegment(text: "Pause resume test", startTime: 0.0, endTime: 2.0, speaker: "Speaker 1"),
        ]
        let chunks = makeTestChunks(count: 1)

        let (controller, playbackService, _, _, _) = await makeController(
            chunks: chunks,
            duration: 10.0,
            segments: segments
        )

        let testFileURL = URL(fileURLWithPath: "/tmp/test-recording-pause.wav")

        // Start playback
        try await controller.startPlayback(fileURL: testFileURL, title: "Pause Test")
        try await Task.sleep(nanoseconds: 100_000_000)

        // Pause
        await controller.pause()

        let pausedState = await playbackService.state
        #expect(pausedState == .paused)

        // Resume
        try await controller.resume()

        let resumedState = await playbackService.state
        #expect(resumedState == .playing)

        // Stop
        try await controller.stopPlayback()

        let stoppedState = await playbackService.state
        #expect(stoppedState == .stopped)
    }

    // MARK: - Test 9: Cascade delete removes transcript segments

    @Test("Deleting a meeting removes its transcript segments and speaker labels")
    func cascadeDeleteRemovesRelatedRecords() async throws {
        let segments = [
            TranscriptSegment(text: "Will be deleted", startTime: 0.0, endTime: 2.0, speaker: "Speaker 1"),
        ]
        let chunks = makeTestChunks(count: 1)

        let (controller, _, _, meetingRepository, _) = await makeController(
            chunks: chunks,
            duration: 5.0,
            segments: segments
        )

        let testFileURL = URL(fileURLWithPath: "/tmp/test-recording-delete.wav")

        // Create and complete a session
        try await controller.startPlayback(fileURL: testFileURL, title: "Delete Test")
        try await Task.sleep(nanoseconds: 150_000_000)
        try await controller.stopPlayback()

        let meetings = await meetingRepository.meetings
        let meetingId = meetings[0].id

        // Add speaker labels
        let label = SpeakerLabelRecord(
            id: UUID().uuidString,
            meetingId: meetingId,
            originalLabel: "Speaker 1",
            customLabel: "Test",
            color: "#FF0000",
            createdAt: Date()
        )
        try await meetingRepository.upsertSpeakerLabel(label)

        // Verify data exists
        var transcriptCount = (try await meetingRepository.getTranscript(meetingId: meetingId)).count
        var labelCount = (try await meetingRepository.getSpeakerLabels(meetingId: meetingId)).count
        #expect(transcriptCount >= 1)
        #expect(labelCount == 1)

        // Delete meeting (cascade should remove related records)
        try await meetingRepository.delete(id: meetingId)

        // Verify cascade removal
        let remainingMeetings = await meetingRepository.meetings
        #expect(remainingMeetings.isEmpty)

        transcriptCount = (try await meetingRepository.getTranscript(meetingId: meetingId)).count
        labelCount = (try await meetingRepository.getSpeakerLabels(meetingId: meetingId)).count
        #expect(transcriptCount == 0, "Transcript segments should be cascade-deleted")
        #expect(labelCount == 0, "Speaker labels should be cascade-deleted")
    }

    // MARK: - Test 10: Multiple playback sessions tracked independently

    @Test("Multiple playback sessions tracked independently in repository")
    func multiplePlaybackSessionsTrackedIndependently() async throws {
        let meetingRepository = IntegrationMockMeetingRepository()
        let embeddingPipeline = IntegrationMockEmbeddingPipeline()

        // Session 1
        let playbackService1 = IntegrationMockPlaybackService()
        let transcriptionPipeline1 = IntegrationMockTranscriptionPipeline()
        await playbackService1.configure(duration: 10.0, chunks: makeTestChunks(count: 1))
        await transcriptionPipeline1.setSegments([
            TranscriptSegment(text: "Session one text", startTime: 0.0, endTime: 5.0, speaker: "Speaker A"),
        ])

        let controller1 = PlaybackSessionController(
            playbackService: playbackService1,
            transcriptionPipeline: transcriptionPipeline1,
            meetingRepository: meetingRepository,
            embeddingPipeline: embeddingPipeline
        )

        try await controller1.startPlayback(
            fileURL: URL(fileURLWithPath: "/tmp/recording1.wav"),
            title: "Session 1"
        )
        try await Task.sleep(nanoseconds: 150_000_000)
        try await controller1.stopPlayback()

        // Session 2
        let playbackService2 = IntegrationMockPlaybackService()
        let transcriptionPipeline2 = IntegrationMockTranscriptionPipeline()
        await playbackService2.configure(duration: 20.0, chunks: makeTestChunks(count: 2))
        await transcriptionPipeline2.setSegments([
            TranscriptSegment(text: "Session two text", startTime: 0.0, endTime: 8.0, speaker: "Speaker B"),
            TranscriptSegment(text: "Session two continued", startTime: 8.0, endTime: 16.0, speaker: "Speaker C"),
        ])

        let controller2 = PlaybackSessionController(
            playbackService: playbackService2,
            transcriptionPipeline: transcriptionPipeline2,
            meetingRepository: meetingRepository,
            embeddingPipeline: embeddingPipeline
        )

        try await controller2.startPlayback(
            fileURL: URL(fileURLWithPath: "/tmp/recording2.wav"),
            title: "Session 2"
        )
        try await Task.sleep(nanoseconds: 150_000_000)
        try await controller2.stopPlayback()

        // Verify both meetings exist
        let allMeetings = await meetingRepository.meetings
        #expect(allMeetings.count == 2)

        let session1 = allMeetings.first { $0.title == "Session 1" }
        let session2 = allMeetings.first { $0.title == "Session 2" }
        #expect(session1 != nil)
        #expect(session2 != nil)
        #expect(session1?.mode == "playback")
        #expect(session2?.mode == "playback")

        // Verify transcripts are isolated to their meetings
        let transcript1 = try await meetingRepository.getTranscript(meetingId: session1!.id)
        let transcript2 = try await meetingRepository.getTranscript(meetingId: session2!.id)

        #expect(transcript1.count == 1)
        #expect(transcript1[0].text == "Session one text")

        #expect(transcript2.count == 2)
        #expect(transcript2[0].text == "Session two text")
        #expect(transcript2[1].text == "Session two continued")
    }
}

// MARK: - Database Integration Tests (Real GRDB)

@Suite("Recording Playback Database Integration Tests")
struct RecordingPlaybackDatabaseIntegrationTests {

    private func makeDatabase() throws -> (GophyDatabase, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GophyPlaybackIntTests-\(UUID().uuidString)")
        let storageManager = StorageManager(baseDirectory: tempDir)
        let database = try GophyDatabase(storageManager: storageManager)
        return (database, tempDir)
    }

    @Test("Recording metadata columns exist after migration v12")
    func recordingMetadataColumnsExist() throws {
        let (database, tempDir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try database.dbQueue.read { db in
            let columns = try db.columns(in: "meetings").map { $0.name }
            #expect(columns.contains("sourceFilePath"))
            #expect(columns.contains("speakerCount"))
        }
    }

    @Test("Speaker labels table exists with correct schema")
    func speakerLabelsTableExists() throws {
        let (database, tempDir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try database.dbQueue.read { db in
            let tableExists = try db.tableExists("speaker_labels")
            #expect(tableExists)

            let columns = try db.columns(in: "speaker_labels").map { $0.name }
            #expect(columns.contains("id"))
            #expect(columns.contains("meetingId"))
            #expect(columns.contains("originalLabel"))
            #expect(columns.contains("customLabel"))
            #expect(columns.contains("color"))
            #expect(columns.contains("createdAt"))
        }
    }

    @Test("MeetingRecord with sourceFilePath and speakerCount round-trips through DB")
    func meetingRecordWithPlaybackFieldsRoundTrips() throws {
        let (database, tempDir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let meeting = MeetingRecord(
            id: UUID().uuidString,
            title: "Playback Meeting",
            startedAt: Date(),
            endedAt: Date(),
            mode: "playback",
            status: "completed",
            createdAt: Date(),
            sourceFilePath: "/path/to/recording.wav",
            speakerCount: 3
        )

        try database.dbQueue.write { db in
            try meeting.insert(db)
        }

        let fetched = try database.dbQueue.read { db in
            try MeetingRecord.fetchOne(db, key: meeting.id)
        }

        #expect(fetched != nil)
        #expect(fetched?.sourceFilePath == "/path/to/recording.wav")
        #expect(fetched?.speakerCount == 3)
        #expect(fetched?.mode == "playback")
    }

    @Test("SpeakerLabelRecord CRUD operations work correctly")
    func speakerLabelRecordCRUD() throws {
        let (database, tempDir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let meetingId = UUID().uuidString
        let meeting = MeetingRecord(
            id: meetingId,
            title: "Speaker Test",
            startedAt: Date(),
            endedAt: nil,
            mode: "playback",
            status: "active",
            createdAt: Date()
        )

        let label = SpeakerLabelRecord(
            id: UUID().uuidString,
            meetingId: meetingId,
            originalLabel: "Speaker 1",
            customLabel: "Alice",
            color: "#3B82F6",
            createdAt: Date()
        )

        try database.dbQueue.write { db in
            try meeting.insert(db)
            try label.insert(db)
        }

        // Read
        let fetched = try database.dbQueue.read { db in
            try SpeakerLabelRecord.fetchOne(db, key: label.id)
        }

        #expect(fetched != nil)
        #expect(fetched?.meetingId == meetingId)
        #expect(fetched?.originalLabel == "Speaker 1")
        #expect(fetched?.customLabel == "Alice")
        #expect(fetched?.color == "#3B82F6")

        // Update (using save for upsert)
        let updatedLabel = SpeakerLabelRecord(
            id: label.id,
            meetingId: meetingId,
            originalLabel: "Speaker 1",
            customLabel: "Alice Smith",
            color: "#3B82F6",
            createdAt: label.createdAt
        )

        try database.dbQueue.write { db in
            try updatedLabel.save(db)
        }

        let reFetched = try database.dbQueue.read { db in
            try SpeakerLabelRecord.fetchOne(db, key: label.id)
        }
        #expect(reFetched?.customLabel == "Alice Smith")

        // Delete
        try database.dbQueue.write { db in
            _ = try SpeakerLabelRecord.deleteOne(db, key: label.id)
        }

        let afterDelete = try database.dbQueue.read { db in
            try SpeakerLabelRecord.fetchOne(db, key: label.id)
        }
        #expect(afterDelete == nil)
    }

    @Test("Cascade delete of meeting removes speaker labels")
    func cascadeDeleteRemovesSpeakerLabels() throws {
        let (database, tempDir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let meetingId = UUID().uuidString
        let meeting = MeetingRecord(
            id: meetingId,
            title: "Cascade Test",
            startedAt: Date(),
            endedAt: nil,
            mode: "playback",
            status: "active",
            createdAt: Date()
        )

        let label1 = SpeakerLabelRecord(
            id: UUID().uuidString,
            meetingId: meetingId,
            originalLabel: "Speaker 1",
            customLabel: "Alice",
            color: "#3B82F6",
            createdAt: Date()
        )
        let label2 = SpeakerLabelRecord(
            id: UUID().uuidString,
            meetingId: meetingId,
            originalLabel: "Speaker 2",
            customLabel: "Bob",
            color: "#10B981",
            createdAt: Date()
        )

        try database.dbQueue.write { db in
            try meeting.insert(db)
            try label1.insert(db)
            try label2.insert(db)
        }

        // Verify labels exist
        let beforeCount = try database.dbQueue.read { db in
            try SpeakerLabelRecord.filter(Column("meetingId") == meetingId).fetchCount(db)
        }
        #expect(beforeCount == 2)

        // Delete meeting
        try database.dbQueue.write { db in
            _ = try MeetingRecord.deleteOne(db, key: meetingId)
        }

        // Verify labels are cascade-deleted
        let afterCount = try database.dbQueue.read { db in
            try SpeakerLabelRecord.filter(Column("meetingId") == meetingId).fetchCount(db)
        }
        #expect(afterCount == 0)
    }

    @Test("Existing meetings without playback fields have nil sourceFilePath and speakerCount")
    func existingMeetingsHaveNilPlaybackFields() throws {
        let (database, tempDir) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Insert a regular meeting without playback fields
        let meeting = MeetingRecord(
            id: UUID().uuidString,
            title: "Regular Meeting",
            startedAt: Date(),
            endedAt: nil,
            mode: "meeting",
            status: "active",
            createdAt: Date()
        )

        try database.dbQueue.write { db in
            try meeting.insert(db)
        }

        let fetched = try database.dbQueue.read { db in
            try MeetingRecord.fetchOne(db, key: meeting.id)
        }

        #expect(fetched != nil)
        #expect(fetched?.sourceFilePath == nil)
        #expect(fetched?.speakerCount == nil)
        #expect(fetched?.mode == "meeting")
    }
}
