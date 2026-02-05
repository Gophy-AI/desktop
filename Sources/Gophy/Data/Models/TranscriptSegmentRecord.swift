import Foundation
import GRDB

public struct TranscriptSegmentRecord: Codable, Sendable {
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

extension TranscriptSegmentRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "transcript_segments"
}
