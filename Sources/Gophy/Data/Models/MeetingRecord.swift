import Foundation
import GRDB

public struct MeetingRecord: Codable, Sendable {
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

extension MeetingRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "meetings"
}
