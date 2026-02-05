import Foundation
import GRDB

public struct VectorSearchResult: Sendable {
    public let id: String
    public let distance: Float

    public init(id: String, distance: Float) {
        self.id = id
        self.distance = distance
    }
}

public final class VectorSearchService: Sendable {
    private let database: GophyDatabase

    public init(database: GophyDatabase) {
        self.database = database
    }

    public func insert(id: String, embedding: [Float]) async throws {
        guard embedding.count == 768 else {
            throw VectorSearchError.invalidEmbeddingDimension
        }

        let blob = embedding.withUnsafeBytes { Data($0) }

        try await database.dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO embeddings(embedding) VALUES (?)",
                arguments: [blob]
            )
            let rowId = db.lastInsertedRowID
            try db.execute(
                sql: "INSERT OR REPLACE INTO embedding_id_mapping(rowid, chunk_id) VALUES (?, ?)",
                arguments: [rowId, id]
            )
        }
    }

    public func search(query: [Float], limit: Int) async throws -> [VectorSearchResult] {
        guard query.count == 768 else {
            throw VectorSearchError.invalidEmbeddingDimension
        }

        let queryBlob = query.withUnsafeBytes { Data($0) }

        return try await database.dbQueue.read { db -> [VectorSearchResult] in
            let sql = """
                SELECT rowid, distance
                FROM embeddings
                WHERE embedding MATCH ?
                ORDER BY distance
                LIMIT ?
                """

            let rows = try Row.fetchAll(db, sql: sql, arguments: [queryBlob, limit])

            var searchResults: [VectorSearchResult] = []
            for row in rows {
                let rowId: Int64 = row["rowid"]
                let distance: Float = row["distance"]

                if let chunkId = try String.fetchOne(
                    db,
                    sql: "SELECT chunk_id FROM embedding_id_mapping WHERE rowid = ?",
                    arguments: [rowId]
                ) {
                    searchResults.append(VectorSearchResult(id: chunkId, distance: distance))
                }
            }
            return searchResults
        }
    }

    public func delete(id: String) async throws {
        try await database.dbQueue.write { db in
            guard let rowId = try Int64.fetchOne(
                db,
                sql: "SELECT rowid FROM embedding_id_mapping WHERE chunk_id = ?",
                arguments: [id]
            ) else {
                return
            }

            try db.execute(
                sql: "DELETE FROM embeddings WHERE rowid = ?",
                arguments: [rowId]
            )
            try db.execute(
                sql: "DELETE FROM embedding_id_mapping WHERE rowid = ?",
                arguments: [rowId]
            )
        }
    }

    public func count() async throws -> Int {
        try await database.dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM embeddings") ?? 0
        }
    }
}

public enum VectorSearchError: Error {
    case invalidEmbeddingDimension
}
