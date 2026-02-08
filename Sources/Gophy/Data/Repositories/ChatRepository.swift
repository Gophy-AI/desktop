import Foundation
import GRDB

public final class ChatRepository: Sendable {
    private let database: GophyDatabase

    public init(database: GophyDatabase) {
        self.database = database
    }

    public func create(_ chat: ChatRecord) async throws {
        try await database.dbQueue.write { db in
            try chat.insert(db)
        }
    }

    public func listAll() async throws -> [ChatRecord] {
        try await database.dbQueue.read { db in
            try ChatRecord
                .order(Column("isPredefined").desc, Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    public func listByContextType(_ type: String) async throws -> [ChatRecord] {
        try await database.dbQueue.read { db in
            try ChatRecord
                .filter(Column("contextType") == type)
                .order(Column("isPredefined").desc, Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    public func findByContextId(_ contextId: String) async throws -> ChatRecord? {
        try await database.dbQueue.read { db in
            try ChatRecord
                .filter(Column("contextId") == contextId)
                .order(Column("updatedAt").desc)
                .fetchOne(db)
        }
    }

    public func update(_ chat: ChatRecord) async throws {
        try await database.dbQueue.write { db in
            try chat.update(db)
        }
    }

    @discardableResult
    public func delete(id: String) async throws -> Bool {
        try await database.dbQueue.write { db in
            if let chat = try ChatRecord.fetchOne(db, key: id), chat.isPredefined {
                return false
            }
            return try ChatRecord.deleteOne(db, key: id)
        }
    }

    public func ensurePredefinedChatsExist() async throws {
        try await database.dbQueue.write { db in
            let now = Date()
            let predefinedChats: [(String, String, String)] = [
                ("predefined-all", "All", "all"),
                ("predefined-meetings", "Meetings", "meetings"),
                ("predefined-documents", "Documents", "documents"),
            ]
            for (id, title, contextType) in predefinedChats {
                let exists = try ChatRecord.fetchOne(db, key: id) != nil
                if !exists {
                    let chat = ChatRecord(
                        id: id,
                        title: title,
                        contextType: contextType,
                        contextId: nil,
                        isPredefined: true,
                        createdAt: now,
                        updatedAt: now
                    )
                    try chat.insert(db)
                }
            }
        }
    }
}
