import Foundation
import GRDB

public struct MeetingRecord: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let startedAt: Date
    public let endedAt: Date?
    public let mode: String
    public let status: String
    public let createdAt: Date
    public let sourceFilePath: String?
    public let speakerCount: Int?
    public let calendarEventId: String?
    public let calendarTitle: String?

    public init(
        id: String,
        title: String,
        startedAt: Date,
        endedAt: Date?,
        mode: String,
        status: String,
        createdAt: Date,
        sourceFilePath: String? = nil,
        speakerCount: Int? = nil,
        calendarEventId: String? = nil,
        calendarTitle: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.mode = mode
        self.status = status
        self.createdAt = createdAt
        self.sourceFilePath = sourceFilePath
        self.speakerCount = speakerCount
        self.calendarEventId = calendarEventId
        self.calendarTitle = calendarTitle
    }
}

extension MeetingRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "meetings"
}
