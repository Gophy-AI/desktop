import Foundation
import GRDB

public struct DocumentRecord: Codable, Sendable {
    public let id: String
    public let name: String
    public let type: String
    public let path: String
    public let status: String
    public let pageCount: Int
    public let createdAt: Date

    public init(
        id: String,
        name: String,
        type: String,
        path: String,
        status: String,
        pageCount: Int,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.path = path
        self.status = status
        self.pageCount = pageCount
        self.createdAt = createdAt
    }
}

extension DocumentRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "documents"
}
