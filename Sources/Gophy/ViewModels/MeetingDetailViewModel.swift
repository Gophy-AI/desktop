import Foundation
import SwiftUI

@MainActor
@Observable
public final class MeetingDetailViewModel {
    private let meetingRepository: MeetingRepository
    private let chatMessageRepository: ChatMessageRepository

    public let meeting: MeetingRecord
    public var transcriptSegments: [TranscriptSegmentRecord] = []
    public var suggestions: [ChatMessageRecord] = []
    public var errorMessage: String?
    public var isLoading = false
    public var selectedTab: DetailTab = .transcript

    public enum DetailTab: String, CaseIterable {
        case transcript = "Transcript"
        case suggestions = "Suggestions"
    }

    public init(
        meeting: MeetingRecord,
        meetingRepository: MeetingRepository,
        chatMessageRepository: ChatMessageRepository
    ) {
        self.meeting = meeting
        self.meetingRepository = meetingRepository
        self.chatMessageRepository = chatMessageRepository
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
}
