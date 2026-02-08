import Foundation
import GRDB

public final class ChatMessageRepository: Sendable {
    private let database: GophyDatabase

    public init(database: GophyDatabase) {
        self.database = database
    }

    public func create(_ message: ChatMessageRecord) async throws {
        try await database.dbQueue.write { db in
            try message.insert(db)
        }
    }

    public func listForMeeting(meetingId: String) async throws -> [ChatMessageRecord] {
        try await database.dbQueue.read { db in
            try ChatMessageRecord
                .filter(Column("meetingId") == meetingId)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    public func listGlobal() async throws -> [ChatMessageRecord] {
        try await database.dbQueue.read { db in
            try ChatMessageRecord
                .filter(Column("meetingId") == nil)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    public func listForChat(chatId: String) async throws -> [ChatMessageRecord] {
        try await database.dbQueue.read { db in
            try ChatMessageRecord
                .filter(Column("chatId") == chatId)
                .order(Column("createdAt").asc)
                .fetchAll(db)
        }
    }

    public func deleteAllForChat(chatId: String) async throws {
        try await database.dbQueue.write { db in
            _ = try ChatMessageRecord
                .filter(Column("chatId") == chatId)
                .deleteAll(db)
        }
    }

    public func delete(id: String) async throws {
        try await database.dbQueue.write { db in
            _ = try ChatMessageRecord.deleteOne(db, key: id)
        }
    }
}

extension ChatMessageRepository: ChatMessageRepoForSuggestion {}
