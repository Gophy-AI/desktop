import Foundation

// MARK: - Protocols for Dependencies

public protocol ModeControllerProtocol: Sendable {
    func switchMode(_ mode: Mode) async throws
}

extension ModeController: ModeControllerProtocol {}

public protocol TranscriptionPipelineProtocol: Sendable {
    nonisolated func start(mixedStream: AsyncStream<LabeledAudioChunk>) -> AsyncStream<TranscriptSegment>
    func stop() async
}

extension TranscriptionPipeline: TranscriptionPipelineProtocol {}

public protocol MeetingRepositoryProtocol: Sendable {
    func create(_ meeting: MeetingRecord) async throws
    func update(_ meeting: MeetingRecord) async throws
    func get(id: String) async throws -> MeetingRecord?
    func listAll(limit: Int?, offset: Int) async throws -> [MeetingRecord]
    func delete(id: String) async throws
    func addTranscriptSegment(_ segment: TranscriptSegmentRecord) async throws
    func getTranscript(meetingId: String) async throws -> [TranscriptSegmentRecord]
    func getSegment(id: String) async throws -> TranscriptSegmentRecord?
    func search(query: String) async throws -> [MeetingRecord]
    func findOrphaned() async throws -> [MeetingRecord]
}

extension MeetingRepository: MeetingRepositoryProtocol {}

public protocol EmbeddingPipelineProtocol: Sendable {
    func indexMeeting(meetingId: String) async throws
    func indexDocument(documentId: String) async throws
    func indexTranscriptSegment(segment: TranscriptSegmentRecord) async throws
    func indexDocumentChunk(chunk: DocumentChunkRecord) async throws
}

extension EmbeddingPipeline: EmbeddingPipelineProtocol {}

public protocol AudioMixerProtocol: Sendable {
    func start() -> AsyncStream<LabeledAudioChunk>
}

extension AudioMixer: AudioMixerProtocol {}

// MARK: - MeetingSessionController

public actor MeetingSessionController {
    private let modeController: any ModeControllerProtocol
    private let transcriptionPipeline: any TranscriptionPipelineProtocol
    private let meetingRepository: any MeetingRepositoryProtocol
    private let embeddingPipeline: any EmbeddingPipelineProtocol
    private let microphoneCapture: any MicrophoneCaptureProtocol
    private let systemAudioCapture: any SystemAudioCaptureProtocol
    private let audioMixer: any AudioMixerProtocol

    private var currentMeetingId: String?
    private var currentStatus: MeetingStatus = .idle
    private var eventContinuation: AsyncStream<MeetingEvent>.Continuation?
    private var transcriptionTask: Task<Void, Never>?

    public nonisolated let eventStream: AsyncStream<MeetingEvent>

    private func setEventContinuation(_ continuation: AsyncStream<MeetingEvent>.Continuation) {
        self.eventContinuation = continuation
    }

    public init(
        modeController: any ModeControllerProtocol,
        transcriptionPipeline: any TranscriptionPipelineProtocol,
        meetingRepository: any MeetingRepositoryProtocol,
        embeddingPipeline: any EmbeddingPipelineProtocol,
        microphoneCapture: any MicrophoneCaptureProtocol,
        systemAudioCapture: any SystemAudioCaptureProtocol,
        audioMixer: any AudioMixerProtocol
    ) {
        self.modeController = modeController
        self.transcriptionPipeline = transcriptionPipeline
        self.meetingRepository = meetingRepository
        self.embeddingPipeline = embeddingPipeline
        self.microphoneCapture = microphoneCapture
        self.systemAudioCapture = systemAudioCapture
        self.audioMixer = audioMixer

        var continuation: AsyncStream<MeetingEvent>.Continuation?
        self.eventStream = AsyncStream { cont in
            continuation = cont
        }
        self.eventContinuation = continuation
    }

    public func recoverOrphanedMeetings() async throws -> [MeetingRecord] {
        let orphanedMeetings = try await meetingRepository.findOrphaned()
        let currentTime = Date()

        for meeting in orphanedMeetings {
            let updatedMeeting = MeetingRecord(
                id: meeting.id,
                title: meeting.title,
                startedAt: meeting.startedAt,
                endedAt: currentTime,
                mode: meeting.mode,
                status: "interrupted",
                createdAt: meeting.createdAt
            )
            try await meetingRepository.update(updatedMeeting)
        }

        return orphanedMeetings
    }

    public func start(title: String) async throws {
        guard currentStatus == .idle || currentStatus == .completed else {
            throw MeetingSessionError.sessionAlreadyActive
        }

        updateStatus(.starting)

        // Switch to meeting mode (loads transcription + text generation engines)
        try await modeController.switchMode(.meeting)

        // Create meeting record
        let meetingId = UUID().uuidString
        let meeting = MeetingRecord(
            id: meetingId,
            title: title,
            startedAt: Date(),
            endedAt: nil,
            mode: "meeting",
            status: "active",
            createdAt: Date()
        )
        try await meetingRepository.create(meeting)
        currentMeetingId = meetingId

        // Start audio capture
        _ = microphoneCapture.start()
        _ = systemAudioCapture.start()

        // Create audio mixer from both streams
        let mixedStream = audioMixer.start()

        // Start transcription pipeline
        let transcriptStream = transcriptionPipeline.start(mixedStream: mixedStream)

        // Process transcript segments
        transcriptionTask = Task {
            for await segment in transcriptStream {
                await handleTranscriptSegment(segment, meetingId: meetingId)
            }
        }

        updateStatus(.active)
    }

    public func stop() async throws {
        guard let meetingId = currentMeetingId else {
            throw MeetingSessionError.noActiveSession
        }

        updateStatus(.stopping)

        // Stop audio capture
        await microphoneCapture.stop()
        await systemAudioCapture.stop()

        // Stop transcription pipeline (flushes buffers)
        await transcriptionPipeline.stop()

        // Wait for transcription task to complete
        transcriptionTask?.cancel()
        transcriptionTask = nil

        // Update meeting record with endedAt and completed status
        guard let meeting = try await meetingRepository.get(id: meetingId) else {
            throw MeetingSessionError.meetingNotFound
        }

        let updatedMeeting = MeetingRecord(
            id: meeting.id,
            title: meeting.title,
            startedAt: meeting.startedAt,
            endedAt: Date(),
            mode: meeting.mode,
            status: "completed",
            createdAt: meeting.createdAt
        )
        try await meetingRepository.update(updatedMeeting)

        // Index meeting for vector search
        try await embeddingPipeline.indexMeeting(meetingId: meetingId)

        currentMeetingId = nil
        updateStatus(.completed)
    }

    public func pause() async {
        guard currentStatus == .active else {
            return
        }

        updateStatus(.paused)

        // Stop audio capture without ending meeting
        await microphoneCapture.stop()
        await systemAudioCapture.stop()
    }

    public func resume() async throws {
        guard currentStatus == .paused else {
            throw MeetingSessionError.sessionNotPaused
        }

        guard let meetingId = currentMeetingId else {
            throw MeetingSessionError.noActiveSession
        }

        // Restart audio capture
        _ = microphoneCapture.start()
        _ = systemAudioCapture.start()

        // Restart mixer and transcription (pipeline already configured)
        let mixedStream = audioMixer.start()
        let transcriptStream = transcriptionPipeline.start(mixedStream: mixedStream)

        // Resume processing transcript segments
        transcriptionTask = Task {
            for await segment in transcriptStream {
                await handleTranscriptSegment(segment, meetingId: meetingId)
            }
        }

        updateStatus(.active)
    }

    private func handleTranscriptSegment(_ segment: TranscriptSegment, meetingId: String) async {
        // Emit event
        eventContinuation?.yield(.transcriptSegment(segment))

        // Persist to database
        let segmentRecord = TranscriptSegmentRecord(
            id: UUID().uuidString,
            meetingId: meetingId,
            text: segment.text,
            speaker: segment.speaker,
            startTime: segment.startTime,
            endTime: segment.endTime,
            createdAt: Date()
        )

        do {
            try await meetingRepository.addTranscriptSegment(segmentRecord)
        } catch {
            eventContinuation?.yield(.error(MeetingEvent.ErrorWrapper(error)))
        }
    }

    private func updateStatus(_ status: MeetingStatus) {
        currentStatus = status
        eventContinuation?.yield(.statusChange(status))
    }
}

// MARK: - Errors

public enum MeetingSessionError: Error, LocalizedError, Sendable {
    case sessionAlreadyActive
    case noActiveSession
    case sessionNotPaused
    case meetingNotFound

    public var errorDescription: String? {
        switch self {
        case .sessionAlreadyActive:
            return "A meeting session is already active"
        case .noActiveSession:
            return "No active meeting session"
        case .sessionNotPaused:
            return "Meeting session is not paused"
        case .meetingNotFound:
            return "Meeting record not found"
        }
    }
}
