import Foundation
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "PlaybackSession")

/// Controller for audio file playback sessions with real-time transcription
public actor PlaybackSessionController {
    private let playbackService: any RecordingPlaybackProtocol
    private let transcriptionPipeline: any TranscriptionPipelineProtocol
    private let meetingRepository: any MeetingRepositoryProtocol
    private let embeddingPipeline: any EmbeddingPipelineProtocol

    private var currentMeetingId: String?
    private var currentStatus: MeetingStatus = .idle
    private var eventContinuation: AsyncStream<MeetingEvent>.Continuation?
    private var transcriptionTask: Task<Void, Never>?

    public nonisolated let eventStream: AsyncStream<MeetingEvent>

    public init(
        playbackService: any RecordingPlaybackProtocol,
        transcriptionPipeline: any TranscriptionPipelineProtocol,
        meetingRepository: any MeetingRepositoryProtocol,
        embeddingPipeline: any EmbeddingPipelineProtocol
    ) {
        self.playbackService = playbackService
        self.transcriptionPipeline = transcriptionPipeline
        self.meetingRepository = meetingRepository
        self.embeddingPipeline = embeddingPipeline

        var continuation: AsyncStream<MeetingEvent>.Continuation?
        self.eventStream = AsyncStream { cont in
            continuation = cont
        }
        self.eventContinuation = continuation
    }

    /// Start playback session from audio file
    public func startPlayback(fileURL: URL, title: String) async throws {
        logger.info("Starting playback: \(title, privacy: .public)")

        guard currentStatus == .idle || currentStatus == .completed else {
            throw PlaybackSessionError.sessionAlreadyActive
        }

        updateStatus(.starting)

        // Create meeting record with mode="playback"
        let meetingId = UUID().uuidString
        let meeting = MeetingRecord(
            id: meetingId,
            title: title,
            startedAt: Date(),
            endedAt: nil,
            mode: "playback",
            status: "active",
            createdAt: Date()
        )
        try await meetingRepository.create(meeting)
        currentMeetingId = meetingId

        // Load audio file
        try await playbackService.loadFile(url: fileURL)

        // Start playback and get audio stream
        let audioStream = try await playbackService.play()

        // Convert AudioChunk stream to LabeledAudioChunk stream for pipeline
        let labeledStream = AsyncStream<LabeledAudioChunk> { continuation in
            Task {
                for await chunk in audioStream {
                    let labeledChunk = LabeledAudioChunk(
                        samples: chunk.samples,
                        timestamp: chunk.timestamp,
                        speaker: "Playback"
                    )
                    continuation.yield(labeledChunk)
                }
                continuation.finish()
            }
        }

        // Start transcription pipeline
        let transcriptStream = transcriptionPipeline.start(mixedStream: labeledStream)

        // Process transcript segments
        transcriptionTask = Task {
            for await segment in transcriptStream {
                await handleTranscriptSegment(segment, meetingId: meetingId)
            }
        }

        // Emit initial playback progress
        emitPlaybackProgress()

        updateStatus(.active)
        logger.info("Playback started successfully")
    }

    /// Stop playback session
    public func stopPlayback() async throws {
        guard let meetingId = currentMeetingId else {
            throw PlaybackSessionError.noActiveSession
        }

        updateStatus(.stopping)

        // Stop playback service
        await playbackService.stop()

        // Stop transcription pipeline
        await transcriptionPipeline.stop()

        // Wait for transcription task
        transcriptionTask?.cancel()
        transcriptionTask = nil

        // Update meeting record
        guard let meeting = try await meetingRepository.get(id: meetingId) else {
            throw PlaybackSessionError.meetingNotFound
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

        // Index meeting
        do {
            try await embeddingPipeline.indexMeeting(meetingId: meetingId)
            logger.info("Meeting indexed for vector search")
        } catch {
            logger.warning("Skipping vector indexing: \(error.localizedDescription, privacy: .public)")
        }

        currentMeetingId = nil
        updateStatus(.completed)
        logger.info("Playback stopped successfully")
    }

    /// Pause playback
    public func pause() async {
        guard currentStatus == .active else {
            return
        }

        updateStatus(.paused)
        await playbackService.pause()
    }

    /// Resume playback
    public func resume() async throws {
        guard currentStatus == .paused else {
            throw PlaybackSessionError.sessionNotPaused
        }

        try await playbackService.resume()
        updateStatus(.active)
    }

    /// Seek to time position
    public func seek(to time: TimeInterval) async throws {
        guard currentMeetingId != nil else {
            throw PlaybackSessionError.noActiveSession
        }

        // Stop current transcription
        await transcriptionPipeline.stop()
        transcriptionTask?.cancel()
        transcriptionTask = nil

        // Seek playback
        try await playbackService.seek(to: time)

        // Restart transcription if playing
        if currentStatus == .active {
            let audioStream = try await playbackService.play()
            let labeledStream = AsyncStream<LabeledAudioChunk> { continuation in
                Task {
                    for await chunk in audioStream {
                        let labeledChunk = LabeledAudioChunk(
                            samples: chunk.samples,
                            timestamp: chunk.timestamp,
                            speaker: "Playback"
                        )
                        continuation.yield(labeledChunk)
                    }
                    continuation.finish()
                }
            }

            let transcriptStream = transcriptionPipeline.start(mixedStream: labeledStream)
            transcriptionTask = Task {
                guard let meetingId = currentMeetingId else { return }
                for await segment in transcriptStream {
                    await handleTranscriptSegment(segment, meetingId: meetingId)
                }
            }
        }

        logger.info("Seeked to \(String(format: "%.1f", time), privacy: .public)s")
    }

    /// Set playback speed
    public func setSpeed(_ rate: Float) async {
        await playbackService.setSpeed(rate)
        logger.info("Speed set to \(String(format: "%.2f", rate), privacy: .public)x")
    }

    // MARK: - Private

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

    private func emitPlaybackProgress() {
        Task {
            let currentTime = await playbackService.currentTime
            let duration = await playbackService.duration
            eventContinuation?.yield(.playbackProgress(currentTime: currentTime, duration: duration))
        }
    }
}

// MARK: - Errors

public enum PlaybackSessionError: Error, LocalizedError, Sendable {
    case sessionAlreadyActive
    case noActiveSession
    case sessionNotPaused
    case meetingNotFound

    public var errorDescription: String? {
        switch self {
        case .sessionAlreadyActive:
            return "A playback session is already active"
        case .noActiveSession:
            return "No active playback session"
        case .sessionNotPaused:
            return "Playback session is not paused"
        case .meetingNotFound:
            return "Meeting record not found"
        }
    }
}
