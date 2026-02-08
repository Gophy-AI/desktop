import Foundation
import GRDB
import CSQLiteVec

public final class GophyDatabase: Sendable {
    public let dbQueue: DatabaseQueue

    public init(storageManager: StorageManager) throws {
        let databaseURL = storageManager.databaseDirectory.appendingPathComponent("gophy.db")

        var configuration = Configuration()
        configuration.prepareDatabase { db in
            // Set WAL mode before any transactions
            try db.execute(sql: "PRAGMA journal_mode = WAL")

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

        // Migration to fix embedding dimension from 768 to 384 (MiniLM L6 v2 produces 384-dim embeddings)
        migrator.registerMigration("v9_fix_embedding_dimension") { db in
            // Drop old tables and recreate with correct dimension
            try db.execute(sql: "DROP TABLE IF EXISTS embedding_id_mapping")
            try db.execute(sql: "DROP TABLE IF EXISTS embeddings")

            try db.execute(sql: """
                CREATE VIRTUAL TABLE embeddings USING vec0(
                    embedding FLOAT[384]
                )
                """)

            try db.create(table: "embedding_id_mapping") { t in
                t.column("rowid", .integer).primaryKey()
                t.column("chunk_id", .text).notNull().unique()
            }
            try db.create(index: "idx_embedding_id_mapping_chunk_id", on: "embedding_id_mapping", columns: ["chunk_id"])
        }

        // Migration to reindex embeddings for multilingual-e5-small model
        // Switching from all-MiniLM-L6-v2 to multilingual-e5-small requires re-indexing
        // because embedding spaces differ between models (even with same dimension)
        migrator.registerMigration("v10_reindex_for_multilingual_e5") { db in
            // Drop existing tables to clear all embeddings
            try db.execute(sql: "DROP TABLE IF EXISTS embedding_id_mapping")
            try db.execute(sql: "DROP TABLE IF EXISTS embeddings")

            // Recreate embeddings virtual table with same 384 dimension
            // (multilingual-e5-small produces 384-dim embeddings like all-MiniLM-L6-v2)
            try db.execute(sql: """
                CREATE VIRTUAL TABLE embeddings USING vec0(
                    embedding FLOAT[384]
                )
                """)

            // Recreate embedding_id_mapping table
            try db.create(table: "embedding_id_mapping") { t in
                t.column("rowid", .integer).primaryKey()
                t.column("chunk_id", .text).notNull().unique()
            }

            // Recreate index
            try db.create(index: "idx_embedding_id_mapping_chunk_id", on: "embedding_id_mapping", columns: ["chunk_id"])
        }

        migrator.registerMigration("v11_add_language_to_segments") { db in
            try db.alter(table: "transcript_segments") { t in
                t.add(column: "detectedLanguage", .text)
            }
        }

        migrator.registerMigration("v12_recording_metadata") { db in
            // Add recording-specific columns to meetings table
            try db.alter(table: "meetings") { t in
                t.add(column: "sourceFilePath", .text)
                t.add(column: "speakerCount", .integer)
            }

            // Create speaker_labels table for diarized speaker names and colors
            try db.create(table: "speaker_labels") { t in
                t.column("id", .text).primaryKey()
                t.column("meetingId", .text).notNull()
                    .references("meetings", onDelete: .cascade)
                t.column("originalLabel", .text).notNull()
                t.column("customLabel", .text)
                t.column("color", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "idx_speaker_labels_meetingId", on: "speaker_labels", columns: ["meetingId"])
        }

        migrator.registerMigration("v13_add_calendar_fields_to_meetings") { db in
            try db.alter(table: "meetings") { t in
                t.add(column: "calendarEventId", .text)
                t.add(column: "calendarTitle", .text)
            }
        }

        migrator.registerMigration("v14_create_automation_history") { db in
            try db.create(table: "automation_history") { t in
                t.column("id", .text).primaryKey()
                t.column("toolName", .text).notNull()
                t.column("arguments", .text).notNull()
                t.column("result", .text)
                t.column("status", .text).notNull()
                t.column("triggerSource", .text).notNull()
                t.column("meetingId", .text)
                    .references("meetings", onDelete: .cascade)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(
                index: "idx_automation_history_meetingId",
                on: "automation_history",
                columns: ["meetingId"]
            )
        }

        migrator.registerMigration("v15_add_meetingId_to_documents") { db in
            try db.alter(table: "documents") { t in
                t.add(column: "meetingId", .text)
                    .references("meetings", onDelete: .setNull)
            }
            try db.create(
                index: "idx_documents_meetingId",
                on: "documents",
                columns: ["meetingId"]
            )
        }

        migrator.registerMigration("v16_embedding_metadata") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS embedding_metadata(
                    dimension INTEGER NOT NULL
                )
                """)
            // Store current dimension (384 from previous migrations)
            try db.execute(sql: "INSERT INTO embedding_metadata(dimension) VALUES (384)")
        }

        migrator.registerMigration("v17_create_chats") { db in
            // 1. Create chats table
            try db.create(table: "chats") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("contextType", .text).notNull()
                t.column("contextId", .text)
                t.column("isPredefined", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "idx_chats_contextType", on: "chats", columns: ["contextType"])

            // 2. Insert 3 predefined chats
            let now = Date()
            let predefinedChats: [(String, String, String)] = [
                ("predefined-all", "All", "all"),
                ("predefined-meetings", "Meetings", "meetings"),
                ("predefined-documents", "Documents", "documents"),
            ]
            for (id, title, contextType) in predefinedChats {
                try db.execute(
                    sql: """
                        INSERT INTO chats (id, title, contextType, contextId, isPredefined, createdAt, updatedAt)
                        VALUES (?, ?, ?, NULL, 1, ?, ?)
                        """,
                    arguments: [id, title, contextType, now, now]
                )
            }

            // 3. Add chatId column to chat_messages (nullable)
            try db.alter(table: "chat_messages") { t in
                t.add(column: "chatId", .text)
            }

            // 4. Migrate existing data
            // 4a. Global messages (meetingId IS NULL) -> predefined-all
            try db.execute(sql: """
                UPDATE chat_messages SET chatId = 'predefined-all' WHERE meetingId IS NULL
                """)

            // 4b. Per-meeting messages: create a chat per distinct meetingId
            let meetingIds = try String.fetchAll(db, sql: """
                SELECT DISTINCT meetingId FROM chat_messages WHERE meetingId IS NOT NULL
                """)
            for meetingId in meetingIds {
                let chatId = "chat-meeting-\(meetingId)"
                // Try to get the meeting title for a nicer chat name
                let meetingTitle = try String.fetchOne(db, sql: """
                    SELECT title FROM meetings WHERE id = ?
                    """, arguments: [meetingId])
                let title = meetingTitle ?? "Meeting"

                try db.execute(
                    sql: """
                        INSERT INTO chats (id, title, contextType, contextId, isPredefined, createdAt, updatedAt)
                        VALUES (?, ?, 'meeting', ?, 0, ?, ?)
                        """,
                    arguments: [chatId, title, meetingId, now, now]
                )

                try db.execute(
                    sql: """
                        UPDATE chat_messages SET chatId = ? WHERE meetingId = ?
                        """,
                    arguments: [chatId, meetingId]
                )
            }

            // 5. Create index on chatId
            try db.create(index: "idx_chat_messages_chatId", on: "chat_messages", columns: ["chatId"])

            // 6. Unique index on (contextType, contextId) to prevent duplicate context chats
            try db.execute(sql: "CREATE UNIQUE INDEX idx_chats_context ON chats(contextType, contextId) WHERE contextId IS NOT NULL")
        }

        return migrator
    }
}

public struct DatabaseError: Error {
    public let message: String
}
