import Foundation
import GRDB

public final class DocumentRepository: Sendable {
    private let database: GophyDatabase

    public init(database: GophyDatabase) {
        self.database = database
    }

    public func create(_ document: DocumentRecord) async throws {
        try await database.dbQueue.write { db in
            try document.insert(db)
        }
    }

    public func get(id: String) async throws -> DocumentRecord? {
        try await database.dbQueue.read { db in
            try DocumentRecord.fetchOne(db, key: id)
        }
    }

    public func listAll() async throws -> [DocumentRecord] {
        try await database.dbQueue.read { db in
            try DocumentRecord
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    public func delete(id: String) async throws {
        try await database.dbQueue.write { db in
            _ = try DocumentRecord.deleteOne(db, key: id)
        }
    }

    public func addChunk(_ chunk: DocumentChunkRecord) async throws {
        try await database.dbQueue.write { db in
            try chunk.insert(db)
        }
    }

    public func getChunks(documentId: String) async throws -> [DocumentChunkRecord] {
        try await database.dbQueue.read { db in
            try DocumentChunkRecord
                .filter(Column("documentId") == documentId)
                .order(Column("chunkIndex").asc)
                .fetchAll(db)
        }
    }

    public func updateStatus(id: String, status: String) async throws {
        try await database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE documents SET status = ? WHERE id = ?",
                arguments: [status, id]
            )
        }
    }

    public func getChunk(id: String) async throws -> DocumentChunkRecord? {
        try await database.dbQueue.read { db in
            try DocumentChunkRecord.fetchOne(db, key: id)
        }
    }

    public func linkDocument(documentId: String, meetingId: String) async throws {
        try await database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE documents SET meetingId = ? WHERE id = ?",
                arguments: [meetingId, documentId]
            )
        }
    }

    public func unlinkDocument(documentId: String) async throws {
        try await database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE documents SET meetingId = NULL WHERE id = ?",
                arguments: [documentId]
            )
        }
    }

    public func fetchDocuments(forMeetingId meetingId: String) async throws -> [DocumentRecord] {
        try await database.dbQueue.read { db in
            try DocumentRecord
                .filter(Column("meetingId") == meetingId)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }
}
