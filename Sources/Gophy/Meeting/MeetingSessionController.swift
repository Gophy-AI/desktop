import Foundation
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "MeetingSession")

// MARK: - Protocols for Dependencies

public protocol ModeControllerProtocol: Sendable {
    func switchMode(_ mode: Mode) async throws
}

extension ModeController: ModeControllerProtocol {}

public protocol TranscriptionPipelineProtocol: Sendable {
    nonisolated func start(mixedStream: AsyncStream<LabeledAudioChunk>) -> AsyncStream<TranscriptSegment>
    func stop() async
    func setLanguageHint(_ hint: String?) async
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
    func getSpeakerLabels(meetingId: String) async throws -> [SpeakerLabelRecord]
    func upsertSpeakerLabel(_ label: SpeakerLabelRecord) async throws
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

public protocol MeetingSummaryWritebackProtocol: Sendable {
    func writeBack(
        meetingId: String,
        calendarEventId: String?,
        calendarId: String?,
        existingDescription: String?
    ) async throws
}

extension MeetingSummaryWritebackService: MeetingSummaryWritebackProtocol {}

public actor MeetingSessionController {
    private let modeController: any ModeControllerProtocol
    private let transcriptionPipeline: any TranscriptionPipelineProtocol
    private let meetingRepository: any MeetingRepositoryProtocol
    private let embeddingPipeline: any EmbeddingPipelineProtocol
    private let microphoneCapture: any MicrophoneCaptureProtocol
    private let systemAudioCapture: any SystemAudioCaptureProtocol
    private let writebackService: (any MeetingSummaryWritebackProtocol)?
    private let automationManager: (any AutomationManaging)?

    private var currentMeetingId: String?
    private var currentCalendarEventId: String?
    private var currentStatus: MeetingStatus = .idle
    private var eventContinuation: AsyncStream<MeetingEvent>.Continuation?
    private var transcriptionTask: Task<Void, Never>?
    private var automationTask: Task<Void, Never>?

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
        writebackService: (any MeetingSummaryWritebackProtocol)? = nil,
        automationManager: (any AutomationManaging)? = nil
    ) {
        self.modeController = modeController
        self.transcriptionPipeline = transcriptionPipeline
        self.meetingRepository = meetingRepository
        self.embeddingPipeline = embeddingPipeline
        self.microphoneCapture = microphoneCapture
        self.systemAudioCapture = systemAudioCapture
        self.writebackService = writebackService
        self.automationManager = automationManager

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

    public func start(title: String, calendarEventId: String? = nil) async throws {
        logger.info("Starting meeting: \(title, privacy: .public)")

        guard currentStatus == .idle || currentStatus == .completed else {
            logger.error("Session already active")
            throw MeetingSessionError.sessionAlreadyActive
        }

        updateStatus(.starting)
        logger.info("Status: starting")

        // Switch to meeting mode (loads transcription + text generation engines)
        logger.info("Switching to meeting mode...")
        try await modeController.switchMode(.meeting)
        logger.info("Meeting mode active")

        // Create meeting record
        let meetingId = UUID().uuidString
        let meeting = MeetingRecord(
            id: meetingId,
            title: title,
            startedAt: Date(),
            endedAt: nil,
            mode: "meeting",
            status: "active",
            createdAt: Date(),
            calendarEventId: calendarEventId
        )
        logger.info("Creating meeting record...")
        try await meetingRepository.create(meeting)
        currentMeetingId = meetingId
        currentCalendarEventId = calendarEventId
        logger.info("Meeting record created: \(meetingId, privacy: .public)")

        // Start audio capture and create mixer with the streams
        logger.info("Starting microphone capture...")
        let micStream = microphoneCapture.start()
        logger.info("Microphone capture started")

        logger.info("Starting system audio capture...")
        let systemStream = systemAudioCapture.start()
        logger.info("System audio capture started")

        // Create audio mixer with the capture streams
        logger.info("Creating audio mixer...")
        let audioMixer = AudioMixer(
            microphoneStream: micStream,
            systemAudioStream: systemStream
        )
        let mixedStream = audioMixer.start()
        logger.info("Audio mixer started")

        // Set language hint from user preferences
        if let savedLanguage = UserDefaults.standard.string(forKey: "languagePreference"),
           let language = AppLanguage(rawValue: savedLanguage) {
            await transcriptionPipeline.setLanguageHint(language.isoCode)
        } else {
            await transcriptionPipeline.setLanguageHint(nil)
        }

        // Start transcription pipeline
        logger.info("Starting transcription pipeline...")
        let transcriptStream = transcriptionPipeline.start(mixedStream: mixedStream)
        logger.info("Transcription pipeline started")

        // Create a secondary stream for automation voice triggers
        let (automationTranscriptStream, automationTranscriptContinuation) =
            AsyncStream<TranscriptSegment>.makeStream()

        // Process transcript segments
        transcriptionTask = Task {
            for await segment in transcriptStream {
                await handleTranscriptSegment(segment, meetingId: meetingId)
                automationTranscriptContinuation.yield(segment)
            }
            automationTranscriptContinuation.finish()
        }

        // Activate automations if available
        if let automationManager {
            let automationEvents = await automationManager.activateForMeeting(
                meetingId: meetingId,
                transcriptStream: automationTranscriptStream
            )
            automationTask = Task {
                for await event in automationEvents {
                    eventContinuation?.yield(.automation(event))
                }
            }
        }

        updateStatus(.active)
        logger.info("Meeting started successfully!")
    }

    public func stop() async throws {
        guard let meetingId = currentMeetingId else {
            throw MeetingSessionError.noActiveSession
        }

        updateStatus(.stopping)

        // Deactivate automations
        automationTask?.cancel()
        automationTask = nil
        await automationManager?.deactivate()

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

        // Index meeting for vector search (optional - skip if embedding not available)
        do {
            try await embeddingPipeline.indexMeeting(meetingId: meetingId)
            logger.info("Meeting indexed for vector search")
        } catch {
            logger.warning("Skipping vector indexing: \(error.localizedDescription, privacy: .public)")
        }

        // Trigger summary writeback to Google Calendar if enabled
        if UserDefaults.standard.bool(forKey: "calendarWritebackEnabled"),
           let calendarEventId = currentCalendarEventId {
            do {
                try await writebackService?.writeBack(
                    meetingId: meetingId,
                    calendarEventId: calendarEventId,
                    calendarId: nil,
                    existingDescription: nil
                )
                logger.info("Summary written back to calendar")
            } catch {
                logger.warning("Skipping summary writeback: \(error.localizedDescription, privacy: .public)")
            }
        }

        currentMeetingId = nil
        currentCalendarEventId = nil
        updateStatus(.completed)
        logger.info("Meeting stopped successfully")
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

    public func setTranscriptionLanguage(_ language: AppLanguage) async {
        await transcriptionPipeline.setLanguageHint(language.isoCode)
        logger.info("Transcription language changed to: \(language.displayName, privacy: .public)")
    }

    public func resume() async throws {
        guard currentStatus == .paused else {
            throw MeetingSessionError.sessionNotPaused
        }

        guard let meetingId = currentMeetingId else {
            throw MeetingSessionError.noActiveSession
        }

        // Restart audio capture
        let micStream = microphoneCapture.start()
        let systemStream = systemAudioCapture.start()

        // Create new mixer and restart transcription
        let audioMixer = AudioMixer(
            microphoneStream: micStream,
            systemAudioStream: systemStream
        )
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
            createdAt: Date(),
            detectedLanguage: segment.detectedLanguage?.rawValue
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
