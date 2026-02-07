import Foundation

/// Contextual information about the current meeting, passed to the tool-calling pipeline.
public struct MeetingContext: Sendable {
    /// The ID of the active meeting.
    public let meetingId: String

    /// Recent transcript text for context.
    public let recentTranscript: String

    public init(meetingId: String, recentTranscript: String) {
        self.meetingId = meetingId
        self.recentTranscript = recentTranscript
    }
}
