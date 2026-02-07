import Foundation
import GRDB
import os

private let vsLogger = Logger(subsystem: "com.gophy.app", category: "VectorSearchService")

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
    private let _embeddingDimension: Int

    public var embeddingDimension: Int { _embeddingDimension }

    /// Initialize with explicit dimension. Use 0 to skip dimension validation (auto-detect on first insert).
    public init(database: GophyDatabase, embeddingDimension: Int = 0) {
        self.database = database
        self._embeddingDimension = embeddingDimension
        vsLogger.info("VectorSearchService initialized with dimension=\(embeddingDimension, privacy: .public)")
    }

    /// Ensure the embeddings virtual table matches the given dimension.
    /// Recreates the table if the dimension changed.
    public func ensureDimension(_ dimension: Int) async throws {
        guard dimension > 0 else { return }

        let currentDim = try await detectTableDimension()
        if currentDim == dimension {
            vsLogger.info("Embeddings table dimension matches: \(dimension, privacy: .public)")
            return
        }

        vsLogger.info("Dimension mismatch: table=\(currentDim, privacy: .public) model=\(dimension, privacy: .public), recreating table")
        try await recreateEmbeddingsTable(dimension: dimension)
    }

    private func detectTableDimension() async throws -> Int {
        // sqlite-vec tables store dimension in schema; check by inserting/querying or reading metadata
        // Simplest: try to read the stored dimension from our metadata table
        return try await database.dbQueue.read { db -> Int in
            if let dim = try Int.fetchOne(db, sql: "SELECT dimension FROM embedding_metadata LIMIT 1") {
                return dim
            }
            return 0
        }
    }

    private func recreateEmbeddingsTable(dimension: Int) async throws {
        try await database.dbQueue.write { db in
            // Drop old tables
            try db.execute(sql: "DROP TABLE IF EXISTS embedding_id_mapping")
            try db.execute(sql: "DROP TABLE IF EXISTS embeddings")

            // Recreate with new dimension
            try db.execute(sql: """
                CREATE VIRTUAL TABLE embeddings USING vec0(
                    embedding FLOAT[\(dimension)]
                )
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS embedding_id_mapping(
                    rowid INTEGER PRIMARY KEY,
                    chunk_id TEXT NOT NULL UNIQUE
                )
                """)
            try db.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_embedding_id_mapping_chunk_id
                ON embedding_id_mapping(chunk_id)
                """)

            // Store dimension in metadata
            try db.execute(sql: "CREATE TABLE IF NOT EXISTS embedding_metadata(dimension INTEGER NOT NULL)")
            try db.execute(sql: "DELETE FROM embedding_metadata")
            try db.execute(sql: "INSERT INTO embedding_metadata(dimension) VALUES (?)", arguments: [dimension])

            vsLogger.info("Recreated embeddings table with dimension=\(dimension, privacy: .public)")
        }
    }

    public func insert(id: String, embedding: [Float]) async throws {
        if _embeddingDimension > 0 {
            guard embedding.count == _embeddingDimension else {
                throw VectorSearchError.invalidEmbeddingDimension(expected: _embeddingDimension, got: embedding.count)
            }
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
        if _embeddingDimension > 0 {
            guard query.count == _embeddingDimension else {
                throw VectorSearchError.invalidEmbeddingDimension(expected: _embeddingDimension, got: query.count)
            }
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

public enum VectorSearchError: Error, LocalizedError {
    case invalidEmbeddingDimension(expected: Int, got: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidEmbeddingDimension(let expected, let got):
            return "Invalid embedding dimension: expected \(expected), got \(got)"
        }
    }
}
