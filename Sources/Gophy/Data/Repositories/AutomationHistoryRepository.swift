import Foundation
import GRDB

public final class AutomationHistoryRepository: Sendable {
    private let database: GophyDatabase

    public init(database: GophyDatabase) {
        self.database = database
    }

    public func create(_ record: AutomationHistoryRecord) async throws {
        try await database.dbQueue.write { db in
            try record.insert(db)
        }
    }

    public func get(id: String) async throws -> AutomationHistoryRecord? {
        try await database.dbQueue.read { db in
            try AutomationHistoryRecord.fetchOne(db, key: id)
        }
    }

    public func listForMeeting(meetingId: String) async throws -> [AutomationHistoryRecord] {
        try await database.dbQueue.read { db in
            try AutomationHistoryRecord
                .filter(Column("meetingId") == meetingId)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    public func listAll(limit: Int? = nil) async throws -> [AutomationHistoryRecord] {
        try await database.dbQueue.read { db in
            var request = AutomationHistoryRecord
                .order(Column("createdAt").desc)
            if let limit {
                request = request.limit(limit)
            }
            return try request.fetchAll(db)
        }
    }

    public func updateStatus(id: String, status: String) async throws {
        try await database.dbQueue.write { db in
            try db.execute(
                sql: "UPDATE automation_history SET status = ? WHERE id = ?",
                arguments: [status, id]
            )
        }
    }

    public func delete(id: String) async throws {
        try await database.dbQueue.write { db in
            _ = try AutomationHistoryRecord.deleteOne(db, key: id)
        }
    }
}
