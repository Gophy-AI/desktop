import Foundation
import SwiftUI

@MainActor
@Observable
public final class MeetingDetailViewModel {
    private let meetingRepository: MeetingRepository
    private let chatMessageRepository: ChatMessageRepository
    private let writebackService: (any MeetingSummaryWritebackProtocol)?

    public private(set) var meeting: MeetingRecord
    public var meetingDate: Date
    private var isUpdatingDate = false
    public var transcriptSegments: [TranscriptSegmentRecord] = []
    public var suggestions: [ChatMessageRecord] = []
    public var errorMessage: String?
    public var isLoading = false
    public var isWritingBack = false
    public var selectedTab: DetailTab = .transcript

    public enum DetailTab: String, CaseIterable {
        case transcript = "Transcript"
        case suggestions = "Suggestions"
    }

    public init(
        meeting: MeetingRecord,
        meetingRepository: MeetingRepository,
        chatMessageRepository: ChatMessageRepository,
        writebackService: (any MeetingSummaryWritebackProtocol)? = nil
    ) {
        self.meeting = meeting
        self.meetingDate = meeting.startedAt
        self.meetingRepository = meetingRepository
        self.chatMessageRepository = chatMessageRepository
        self.writebackService = writebackService
    }

    public func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let transcript = meetingRepository.getTranscript(meetingId: meeting.id)
            async let messages = chatMessageRepository.listForMeeting(meetingId: meeting.id)

            transcriptSegments = try await transcript
            suggestions = try await messages
        } catch {
            errorMessage = "Failed to load meeting data: \(error.localizedDescription)"
        }
    }

    public func formatDuration() -> String {
        guard let endedAt = meeting.endedAt else {
            return "--:--"
        }

        let duration = Int(endedAt.timeIntervalSince(meeting.startedAt))
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    public func formatDate() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: meeting.startedAt)
    }

    public func segmentCount() -> Int {
        return transcriptSegments.count
    }

    public func suggestionCount() -> Int {
        return suggestions.count
    }

    public var isImportedRecording: Bool {
        meeting.mode == "playback"
    }

    public func updateMeetingDate(_ newDate: Date) async {
        guard !isUpdatingDate else { return }
        isUpdatingDate = true
        defer { isUpdatingDate = false }

        let duration = meeting.endedAt.map { $0.timeIntervalSince(meeting.startedAt) } ?? 0
        let updated = MeetingRecord(
            id: meeting.id,
            title: meeting.title,
            startedAt: newDate,
            endedAt: newDate.addingTimeInterval(duration),
            mode: meeting.mode,
            status: meeting.status,
            createdAt: meeting.createdAt,
            sourceFilePath: meeting.sourceFilePath,
            speakerCount: meeting.speakerCount,
            calendarEventId: meeting.calendarEventId,
            calendarTitle: meeting.calendarTitle
        )

        do {
            try await meetingRepository.update(updated)
            meeting = updated
        } catch {
            errorMessage = "Failed to update meeting date: \(error.localizedDescription)"
            meetingDate = meeting.startedAt
        }
    }

    public func writeSummaryToCalendar() async {
        guard let writebackService = writebackService else {
            errorMessage = "Summary writeback service not available"
            return
        }

        isWritingBack = true
        defer { isWritingBack = false }

        do {
            try await writebackService.writeBack(
                meetingId: meeting.id,
                calendarEventId: meeting.calendarEventId,
                calendarId: nil,
                existingDescription: nil
            )
        } catch {
            errorMessage = "Failed to write summary: \(error.localizedDescription)"
        }
    }
}
