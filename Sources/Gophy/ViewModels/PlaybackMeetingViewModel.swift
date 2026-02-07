@preconcurrency import AVFoundation
import Foundation
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "PlaybackMeetingVM")

@MainActor
@Observable
public final class PlaybackMeetingViewModel {
    private let sessionController: PlaybackSessionController
    private let meetingRepository: MeetingRepository
    private let suggestionEngine: SuggestionEngine
    private let chatMessageRepository: ChatMessageRepository

    public var title: String
    public var status: MeetingStatus = .idle
    public var transcriptSegments: [TranscriptSegmentRecord] = []
    public var suggestions: [ChatMessageRecord] = []
    public var currentTime: TimeInterval = 0
    public var duration: TimeInterval = 0
    public var speed: Float = 1.0
    public var isPlaying: Bool = false
    public var speakerCount: Int = 0
    public var errorMessage: String?
    public var isGeneratingSuggestion = false
    public var isTranscribingAll = false
    public var transcribeAllProgress: Double = 0
    public var speakerLabels: [String: SpeakerLabelInfo] = [:]

    let fileURL: URL
    let meetingRecord: MeetingRecord

    private var eventTask: Task<Void, Never>?
    private var progressTimer: Timer?

    public struct SpeakerLabelInfo: Sendable {
        public let originalLabel: String
        public var displayLabel: String
        public let color: Color

        public init(originalLabel: String, displayLabel: String, color: Color) {
            self.originalLabel = originalLabel
            self.displayLabel = displayLabel
            self.color = color
        }
    }

    public static let speakerColors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .teal, .indigo, .mint
    ]

    public init(
        meeting: MeetingRecord,
        fileURL: URL,
        sessionController: PlaybackSessionController,
        meetingRepository: MeetingRepository,
        suggestionEngine: SuggestionEngine,
        chatMessageRepository: ChatMessageRepository
    ) {
        self.meetingRecord = meeting
        self.fileURL = fileURL
        self.title = meeting.title
        self.sessionController = sessionController
        self.meetingRepository = meetingRepository
        self.suggestionEngine = suggestionEngine
        self.chatMessageRepository = chatMessageRepository

        startListeningToEvents()
    }

    // MARK: - Playback Controls

    public func startPlayback() async {
        do {
            try await sessionController.startPlayback(fileURL: fileURL, title: title, existingMeetingId: meetingRecord.id)
            duration = await sessionController.playbackService.duration
            startProgressTimer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func togglePlayback() async {
        if isPlaying {
            await pausePlayback()
        } else if status == .paused {
            await resumePlayback()
        } else {
            await startPlayback()
        }
    }

    public func pausePlayback() async {
        await sessionController.pause()
        stopProgressTimer()
    }

    public func resumePlayback() async {
        do {
            try await sessionController.resume()
            startProgressTimer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func stopPlayback() async {
        do {
            try await sessionController.stopPlayback()
            stopProgressTimer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func seek(to time: TimeInterval) async {
        do {
            try await sessionController.seek(to: time)
            currentTime = time
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func setSpeed(_ rate: Float) async {
        speed = rate
        await sessionController.setSpeed(rate)
    }

    // MARK: - Speaker Labels

    public func renameSpeaker(original: String, newName: String) async {
        guard var info = speakerLabels[original] else { return }
        info = SpeakerLabelInfo(
            originalLabel: info.originalLabel,
            displayLabel: newName,
            color: info.color
        )
        speakerLabels[original] = info

        // Persist
        let record = SpeakerLabelRecord(
            id: "\(meetingRecord.id)_\(original)",
            meetingId: meetingRecord.id,
            originalLabel: original,
            customLabel: newName,
            color: info.color.hexString,
            createdAt: Date()
        )

        do {
            try await meetingRepository.upsertSpeakerLabel(record)
        } catch {
            logger.error("Failed to save speaker label: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func displayLabel(for speaker: String) -> String {
        speakerLabels[speaker]?.displayLabel ?? speaker
    }

    public func speakerColor(for speaker: String) -> Color {
        if let info = speakerLabels[speaker] {
            return info.color
        }
        // Default color assignment for unknown speakers
        let hash = abs(speaker.hashValue)
        return Self.speakerColors[hash % Self.speakerColors.count]
    }

    public func seekToSegment(_ segment: TranscriptSegmentRecord) async {
        await seek(to: segment.startTime)
    }

    public func refreshSuggestions() async {
        isGeneratingSuggestion = true
        defer { isGeneratingSuggestion = false }

        do {
            _ = try await suggestionEngine.generateSuggestion(meetingId: meetingRecord.id)
            await loadSuggestions()
        } catch {
            errorMessage = "Failed to generate suggestion: \(error.localizedDescription)"
        }
    }

    // MARK: - Batch Transcription

    public func transcribeAll() async {
        guard !isTranscribingAll else { return }
        isTranscribingAll = true
        transcribeAllProgress = 0
        defer { isTranscribingAll = false }

        do {
            // Read the entire audio file
            let audioData = try AVAudioFileReader.readSamples(from: fileURL)
            let samples = audioData.samples
            let sampleRate = audioData.sampleRate

            // Resample to 16kHz if needed
            let targetRate = 16000
            let processedSamples: [Float]
            if sampleRate != targetRate {
                let ratio = Double(targetRate) / Double(sampleRate)
                let targetLength = Int(Double(samples.count) * ratio)
                var resampled = [Float]()
                resampled.reserveCapacity(targetLength)
                for i in 0..<targetLength {
                    let srcIdx = Double(i) / ratio
                    let idx = Int(srcIdx)
                    let frac = Float(srcIdx - Double(idx))
                    if idx + 1 < samples.count {
                        resampled.append(samples[idx] * (1 - frac) + samples[idx + 1] * frac)
                    } else if idx < samples.count {
                        resampled.append(samples[idx])
                    }
                }
                processedSamples = resampled
            } else {
                processedSamples = samples
            }

            // Process in 30-second chunks (WhisperKit optimal window)
            let chunkDuration = 30
            let chunkSize = targetRate * chunkDuration
            let totalChunks = max(1, (processedSamples.count + chunkSize - 1) / chunkSize)

            // Load transcription engine
            let transcriptionEngine = TranscriptionEngine()
            if !transcriptionEngine.isLoaded {
                try await transcriptionEngine.load()
            }

            let languagePref = UserDefaults.standard.string(forKey: "languagePreference")
            let language = (languagePref == nil || languagePref == "auto") ? nil : languagePref

            // Clear existing segments for this meeting
            transcriptSegments.removeAll()

            for chunkIndex in 0..<totalChunks {
                let start = chunkIndex * chunkSize
                let end = min(start + chunkSize, processedSamples.count)
                let chunk = Array(processedSamples[start..<end])

                let segments = try await transcriptionEngine.transcribe(
                    audioArray: chunk,
                    sampleRate: targetRate,
                    language: language
                )

                let chunkStartTime = Double(start) / Double(targetRate)

                for segment in segments where !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let record = TranscriptSegmentRecord(
                        id: UUID().uuidString,
                        meetingId: meetingRecord.id,
                        text: segment.text,
                        speaker: "Speaker",
                        startTime: chunkStartTime + segment.startTime,
                        endTime: chunkStartTime + segment.endTime,
                        createdAt: Date()
                    )
                    transcriptSegments.append(record)

                    try await meetingRepository.addTranscriptSegment(record)

                    // Assign speaker color
                    let speaker = record.speaker
                    if speakerLabels[speaker] == nil {
                        let colorIndex = speakerLabels.count % Self.speakerColors.count
                        speakerLabels[speaker] = SpeakerLabelInfo(
                            originalLabel: speaker,
                            displayLabel: speaker,
                            color: Self.speakerColors[colorIndex]
                        )
                    }
                }

                transcribeAllProgress = Double(chunkIndex + 1) / Double(totalChunks)
            }

            // Update meeting status
            let updated = MeetingRecord(
                id: meetingRecord.id,
                title: meetingRecord.title,
                startedAt: meetingRecord.startedAt,
                endedAt: meetingRecord.endedAt ?? Date(),
                mode: meetingRecord.mode,
                status: "completed",
                createdAt: meetingRecord.createdAt,
                sourceFilePath: meetingRecord.sourceFilePath,
                speakerCount: speakerLabels.count,
                calendarEventId: meetingRecord.calendarEventId,
                calendarTitle: meetingRecord.calendarTitle
            )
            try await meetingRepository.update(updated)

            logger.info("Transcribe all completed: \(self.transcriptSegments.count) segments")
        } catch {
            errorMessage = "Transcription failed: \(error.localizedDescription)"
            logger.error("Transcribe all failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Data Loading

    func loadExistingData() async {
        do {
            let segments = try await meetingRepository.getTranscript(meetingId: meetingRecord.id)
            transcriptSegments = segments

            let labels = try await meetingRepository.getSpeakerLabels(meetingId: meetingRecord.id)
            for (index, label) in labels.enumerated() {
                let color = Self.speakerColors[index % Self.speakerColors.count]
                speakerLabels[label.originalLabel] = SpeakerLabelInfo(
                    originalLabel: label.originalLabel,
                    displayLabel: label.customLabel ?? label.originalLabel,
                    color: color
                )
            }

            await loadSuggestions()
        } catch {
            logger.error("Failed to load existing data: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private

    private func startListeningToEvents() {
        eventTask = Task { [weak self] in
            guard let self = self else { return }

            for await event in sessionController.eventStream {
                await self.handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: MeetingEvent) async {
        switch event {
        case .transcriptSegment(let segment):
            guard !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { break }
            let record = TranscriptSegmentRecord(
                id: UUID().uuidString,
                meetingId: meetingRecord.id,
                text: segment.text,
                speaker: segment.speaker,
                startTime: segment.startTime,
                endTime: segment.endTime,
                createdAt: Date()
            )
            transcriptSegments.append(record)

            // Assign speaker color if new speaker
            if speakerLabels[segment.speaker] == nil {
                let colorIndex = speakerLabels.count % Self.speakerColors.count
                speakerLabels[segment.speaker] = SpeakerLabelInfo(
                    originalLabel: segment.speaker,
                    displayLabel: segment.speaker,
                    color: Self.speakerColors[colorIndex]
                )
            }

        case .suggestion(let text):
            let message = ChatMessageRecord(
                id: UUID().uuidString,
                role: "assistant",
                content: text,
                meetingId: meetingRecord.id,
                createdAt: Date()
            )
            suggestions.append(message)

        case .statusChange(let newStatus):
            status = newStatus
            isPlaying = newStatus == .active

        case .playbackProgress(let time, let dur):
            currentTime = time
            duration = dur

        case .automation:
            break

        case .error(let error):
            if let wrapper = error as? MeetingEvent.ErrorWrapper {
                errorMessage = wrapper.underlyingError
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func startProgressTimer() {
        stopProgressTimer()
        let controller = sessionController
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isPlaying else { return }
                self.currentTime = await controller.playbackService.currentTime
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func loadSuggestions() async {
        do {
            suggestions = try await chatMessageRepository.listForMeeting(meetingId: meetingRecord.id)
        } catch {
            errorMessage = "Failed to load suggestions: \(error.localizedDescription)"
        }
    }
}

// MARK: - Color hex extension

extension Color {
    var hexString: String {
        guard let components = NSColor(self).usingColorSpace(.deviceRGB) else {
            return "#808080"
        }
        let r = Int(components.redComponent * 255)
        let g = Int(components.greenComponent * 255)
        let b = Int(components.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
