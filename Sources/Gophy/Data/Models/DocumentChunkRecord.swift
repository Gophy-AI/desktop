import Foundation
import GRDB

public struct DocumentChunkRecord: Codable, Sendable {
    public let id: String
    public let documentId: String
    public let content: String
    public let chunkIndex: Int
    public let pageNumber: Int
    public let createdAt: Date

    public init(
        id: String,
        documentId: String,
        content: String,
        chunkIndex: Int,
        pageNumber: Int,
        createdAt: Date
    ) {
        self.id = id
        self.documentId = documentId
        self.content = content
        self.chunkIndex = chunkIndex
        self.pageNumber = pageNumber
        self.createdAt = createdAt
    }
}

extension DocumentChunkRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "document_chunks"
}
