import Foundation
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "SummaryWriteback")

// MARK: - Protocols

protocol SummaryGeneratorProtocol: Sendable {
    func generateSummary(transcript: String) async throws -> String
}

enum SummaryGeneratorError: Error, LocalizedError, Sendable {
    case generationFailed(String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .generationFailed(let message):
            return "Summary generation failed: \(message)"
        case .emptyTranscript:
            return "Cannot generate summary from empty transcript"
        }
    }
}

protocol WritebackMeetingRepositoryProtocol: Sendable {
    func get(id: String) async throws -> MeetingRecord?
    func getTranscript(meetingId: String) async throws -> [TranscriptSegmentRecord]
}

extension MeetingRepository: WritebackMeetingRepositoryProtocol {}

// MARK: - TextGeneration-based Summary Generator

final class TextGenerationSummaryGenerator: SummaryGeneratorProtocol, @unchecked Sendable {
    private let textGenEngine: any TextGenerationForSuggestion

    private let summaryPrompt = """
        Summarize this meeting transcript in 3-5 bullet points. \
        Include key decisions, action items, and follow-ups.
        """

    init(textGenEngine: any TextGenerationForSuggestion) {
        self.textGenEngine = textGenEngine
    }

    func generateSummary(transcript: String) async throws -> String {
        guard !transcript.isEmpty else {
            throw SummaryGeneratorError.emptyTranscript
        }

        var fullSummary = ""
        let stream = textGenEngine.generate(
            prompt: "Meeting transcript:\n\(transcript)\n\nSummary:",
            systemPrompt: summaryPrompt,
            maxTokens: 500
        )

        for await token in stream {
            fullSummary += token
        }

        guard !fullSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SummaryGeneratorError.generationFailed("Generated empty summary")
        }

        return fullSummary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - MeetingSummaryWritebackService

actor MeetingSummaryWritebackService {
    private let apiClient: any GoogleCalendarAPIClientProtocol
    private let summaryGenerator: any SummaryGeneratorProtocol
    private let authService: any GoogleAuthServiceProtocol
    private let meetingRepository: any WritebackMeetingRepositoryProtocol

    init(
        apiClient: any GoogleCalendarAPIClientProtocol,
        summaryGenerator: any SummaryGeneratorProtocol,
        authService: any GoogleAuthServiceProtocol,
        meetingRepository: any WritebackMeetingRepositoryProtocol
    ) {
        self.apiClient = apiClient
        self.summaryGenerator = summaryGenerator
        self.authService = authService
        self.meetingRepository = meetingRepository
    }

    func writeBack(
        meetingId: String,
        calendarEventId: String?,
        calendarId: String?,
        existingDescription: String?
    ) async throws {
        guard let eventId = calendarEventId, !eventId.isEmpty else {
            logger.info("Skipping writeback: no calendarEventId for meeting \(meetingId, privacy: .public)")
            return
        }

        // Verify signed in
        do {
            _ = try await authService.freshAccessToken()
        } catch {
            logger.info("Skipping writeback: not signed in to Google")
            return
        }

        let targetCalendarId = calendarId ?? "primary"

        // Get transcript
        let segments = try await meetingRepository.getTranscript(meetingId: meetingId)
        guard !segments.isEmpty else {
            logger.info("Skipping writeback: no transcript for meeting \(meetingId, privacy: .public)")
            return
        }

        let transcriptText = segments
            .sorted { $0.startTime < $1.startTime }
            .map { "[\($0.speaker)] \($0.text)" }
            .joined(separator: "\n")

        // Generate summary
        let summary = try await summaryGenerator.generateSummary(transcript: transcriptText)

        // Build description with appended summary
        let summaryBlock = "\n\n---\nMeeting Summary (by Gophy):\n\(summary)"
        let updatedDescription: String
        if let existing = existingDescription, !existing.isEmpty {
            updatedDescription = existing + summaryBlock
        } else {
            updatedDescription = summaryBlock.trimmingCharacters(in: .newlines)
        }

        // Write description to event
        try await apiClient.patchEvent(
            calendarId: targetCalendarId,
            eventId: eventId,
            description: updatedDescription
        )

        // Write extended properties
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime]

        let properties: [String: String] = [
            "gophy_summary": summary,
            "gophy_meeting_id": meetingId,
            "gophy_recorded_at": iso8601Formatter.string(from: Date())
        ]

        try await apiClient.patchExtendedProperties(
            calendarId: targetCalendarId,
            eventId: eventId,
            properties: properties
        )

        logger.info("Summary written back to calendar event \(eventId, privacy: .public)")
    }
}
