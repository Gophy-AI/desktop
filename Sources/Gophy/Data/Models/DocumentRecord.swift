import Foundation
import GRDB

public struct DocumentRecord: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let type: String
    public let path: String
    public let status: String
    public let pageCount: Int
    public let createdAt: Date
    public let meetingId: String?

    public init(
        id: String,
        name: String,
        type: String,
        path: String,
        status: String,
        pageCount: Int,
        createdAt: Date,
        meetingId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.path = path
        self.status = status
        self.pageCount = pageCount
        self.createdAt = createdAt
        self.meetingId = meetingId
    }
}

extension DocumentRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "documents"
}
