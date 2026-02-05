import Foundation
import GRDB
import CSQLiteVec

public final class GophyDatabase: Sendable {
    public let dbQueue: DatabaseQueue

    public init(storageManager: StorageManager) throws {
        let databaseURL = storageManager.databaseDirectory.appendingPathComponent("gophy.db")

        var configuration = Configuration()
        configuration.prepareDatabase { db in
            var errorMessage: UnsafeMutablePointer<CChar>?
            let result = sqlite3_vec_init(db.sqliteConnection, &errorMessage, nil)

            if result != SQLITE_OK {
                let message = errorMessage.map { String(cString: $0) } ?? "Unknown error"
                sqlite3_free(errorMessage)
                throw DatabaseError(message: "Failed to load SQLite-vec extension: \(message)")
            }

            sqlite3_free(errorMessage)
        }

        dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)

        try dbQueue.write { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }

        try migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_meetings") { db in
            try db.create(table: "meetings") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime)
                t.column("mode", .text).notNull()
                t.column("status", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v2_create_transcript_segments") { db in
            try db.create(table: "transcript_segments") { t in
                t.column("id", .text).primaryKey()
                t.column("meetingId", .text).notNull()
                    .references("meetings", onDelete: .cascade)
                t.column("text", .text).notNull()
                t.column("speaker", .text).notNull()
                t.column("startTime", .double).notNull()
                t.column("endTime", .double).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "idx_transcript_segments_meetingId", on: "transcript_segments", columns: ["meetingId"])
        }

        migrator.registerMigration("v3_create_documents") { db in
            try db.create(table: "documents") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("type", .text).notNull()
                t.column("path", .text).notNull()
                t.column("status", .text).notNull()
                t.column("pageCount", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }

        migrator.registerMigration("v4_create_document_chunks") { db in
            try db.create(table: "document_chunks") { t in
                t.column("id", .text).primaryKey()
                t.column("documentId", .text).notNull()
                    .references("documents", onDelete: .cascade)
                t.column("content", .text).notNull()
                t.column("chunkIndex", .integer).notNull()
                t.column("pageNumber", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "idx_document_chunks_documentId", on: "document_chunks", columns: ["documentId"])
        }

        migrator.registerMigration("v5_create_chat_messages") { db in
            try db.create(table: "chat_messages") { t in
                t.column("id", .text).primaryKey()
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("meetingId", .text)
                    .references("meetings", onDelete: .cascade)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "idx_chat_messages_meetingId", on: "chat_messages", columns: ["meetingId"])
        }

        migrator.registerMigration("v6_create_settings") { db in
            try db.create(table: "settings") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
            }
        }

        migrator.registerMigration("v7_create_embeddings") { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE embeddings USING vec0(
                    embedding FLOAT[768]
                )
                """)
        }

        migrator.registerMigration("v8_create_embedding_id_mapping") { db in
            try db.create(table: "embedding_id_mapping") { t in
                t.column("rowid", .integer).primaryKey()
                t.column("chunk_id", .text).notNull().unique()
            }
            try db.create(index: "idx_embedding_id_mapping_chunk_id", on: "embedding_id_mapping", columns: ["chunk_id"])
        }

        return migrator
    }
}

public struct DatabaseError: Error {
    public let message: String
}
