import Foundation

public struct ExportedMeeting: Codable, Sendable {
    public let version: Int
    public let meeting: ExportedMeetingData
    public let transcript: [ExportedTranscriptSegment]
    public let suggestions: [String]

    public init(
        version: Int,
        meeting: ExportedMeetingData,
        transcript: [ExportedTranscriptSegment],
        suggestions: [String]
    ) {
        self.version = version
        self.meeting = meeting
        self.transcript = transcript
        self.suggestions = suggestions
    }
}

public struct ExportedMeetingData: Codable, Sendable {
    public let id: String
    public let title: String
    public let startedAt: Date
    public let endedAt: Date?
    public let mode: String
    public let status: String
    public let createdAt: Date

    public init(
        id: String,
        title: String,
        startedAt: Date,
        endedAt: Date?,
        mode: String,
        status: String,
        createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.mode = mode
        self.status = status
        self.createdAt = createdAt
    }
}

public struct ExportedTranscriptSegment: Codable, Sendable {
    public let id: String
    public let meetingId: String
    public let text: String
    public let speaker: String
    public let startTime: Double
    public let endTime: Double
    public let createdAt: Date

    public init(
        id: String,
        meetingId: String,
        text: String,
        speaker: String,
        startTime: Double,
        endTime: Double,
        createdAt: Date
    ) {
        self.id = id
        self.meetingId = meetingId
        self.text = text
        self.speaker = speaker
        self.startTime = startTime
        self.endTime = endTime
        self.createdAt = createdAt
    }
}

public final class MeetingExporter: Sendable {
    public init() {}

    public func exportJSON(
        meeting: MeetingRecord,
        transcript: [TranscriptSegmentRecord],
        suggestions: [String]
    ) throws -> Data {
        let exportedMeeting = ExportedMeetingData(
            id: meeting.id,
            title: meeting.title,
            startedAt: meeting.startedAt,
            endedAt: meeting.endedAt,
            mode: meeting.mode,
            status: meeting.status,
            createdAt: meeting.createdAt
        )

        let exportedTranscript = transcript.map { segment in
            ExportedTranscriptSegment(
                id: segment.id,
                meetingId: segment.meetingId,
                text: segment.text,
                speaker: segment.speaker,
                startTime: segment.startTime,
                endTime: segment.endTime,
                createdAt: segment.createdAt
            )
        }

        let export = ExportedMeeting(
            version: 1,
            meeting: exportedMeeting,
            transcript: exportedTranscript,
            suggestions: suggestions
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        return try encoder.encode(export)
    }

    public func exportMarkdown(
        meeting: MeetingRecord,
        transcript: [TranscriptSegmentRecord],
        suggestions: [String]
    ) -> String {
        var markdown = ""

        // Title
        markdown += "# \(meeting.title)\n\n"

        // Metadata
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        markdown += "**Date:** \(dateFormatter.string(from: meeting.startedAt))\n\n"

        // Duration
        if let endedAt = meeting.endedAt {
            let duration = endedAt.timeIntervalSince(meeting.startedAt)
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            markdown += "**Duration:** \(minutes)m \(seconds)s\n\n"
        }

        markdown += "**Mode:** \(meeting.mode)\n\n"

        // Transcript
        markdown += "## Transcript\n\n"

        for segment in transcript {
            let timestamp = formatTimestamp(segment.startTime)
            markdown += "[\(timestamp)] **\(segment.speaker)**: \(segment.text)\n\n"
        }

        // Suggestions
        if !suggestions.isEmpty {
            markdown += "## Suggestions\n\n"
            for suggestion in suggestions {
                markdown += "- \(suggestion)\n"
            }
            markdown += "\n"
        }

        return markdown
    }

    public func formatTimestamp(_ timeInSeconds: Double) -> String {
        let totalSeconds = Int(timeInSeconds)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    public func suggestedFilename(for meeting: MeetingRecord, format: ExportFormat) -> String {
        let sanitizedTitle = meeting.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: meeting.startedAt)

        switch format {
        case .json:
            return "\(sanitizedTitle)-\(dateString).gophy.json"
        case .markdown:
            return "\(sanitizedTitle)-\(dateString).md"
        }
    }
}

public enum ExportFormat {
    case json
    case markdown
}
