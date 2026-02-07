import Foundation
import GRDB

public struct SpeakerLabelRecord: Codable, Sendable {
    public let id: String
    public let meetingId: String
    public let originalLabel: String
    public let customLabel: String?
    public let color: String
    public let createdAt: Date

    public init(
        id: String,
        meetingId: String,
        originalLabel: String,
        customLabel: String?,
        color: String,
        createdAt: Date
    ) {
        self.id = id
        self.meetingId = meetingId
        self.originalLabel = originalLabel
        self.customLabel = customLabel
        self.color = color
        self.createdAt = createdAt
    }
}

extension SpeakerLabelRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "speaker_labels"
}
