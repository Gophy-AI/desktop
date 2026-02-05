import Foundation
import GRDB

public final class MeetingRepository: Sendable {
    private let database: GophyDatabase

    public init(database: GophyDatabase) {
        self.database = database
    }

    public func create(_ meeting: MeetingRecord) async throws {
        try await database.dbQueue.write { db in
            try meeting.insert(db)
        }
    }

    public func get(id: String) async throws -> MeetingRecord? {
        try await database.dbQueue.read { db in
            try MeetingRecord.fetchOne(db, key: id)
        }
    }

    public func listAll(limit: Int? = nil, offset: Int = 0) async throws -> [MeetingRecord] {
        try await database.dbQueue.read { db in
            var request = MeetingRecord
                .order(Column("startedAt").desc)

            if let limit = limit {
                request = request.limit(limit, offset: offset)
            }

            return try request.fetchAll(db)
        }
    }

    public func update(_ meeting: MeetingRecord) async throws {
        try await database.dbQueue.write { db in
            try meeting.update(db)
        }
    }

    public func delete(id: String) async throws {
        try await database.dbQueue.write { db in
            _ = try MeetingRecord.deleteOne(db, key: id)
        }
    }

    public func addTranscriptSegment(_ segment: TranscriptSegmentRecord) async throws {
        try await database.dbQueue.write { db in
            try segment.insert(db)
        }
    }

    public func getTranscript(meetingId: String) async throws -> [TranscriptSegmentRecord] {
        try await database.dbQueue.read { db in
            try TranscriptSegmentRecord
                .filter(Column("meetingId") == meetingId)
                .order(Column("startTime").asc)
                .fetchAll(db)
        }
    }

    public func getSegment(id: String) async throws -> TranscriptSegmentRecord? {
        try await database.dbQueue.read { db in
            try TranscriptSegmentRecord.fetchOne(db, key: id)
        }
    }

    public func search(query: String) async throws -> [MeetingRecord] {
        try await database.dbQueue.read { db in
            let pattern = "%\(query)%"
            let sql = """
                SELECT DISTINCT meetings.*
                FROM meetings
                INNER JOIN transcript_segments ON meetings.id = transcript_segments.meetingId
                WHERE transcript_segments.text LIKE ?
                ORDER BY meetings.startedAt DESC
                """
            return try MeetingRecord.fetchAll(db, sql: sql, arguments: [pattern])
        }
    }

    public func findOrphaned() async throws -> [MeetingRecord] {
        try await database.dbQueue.read { db in
            try MeetingRecord
                .filter(Column("status") == "active" && Column("endedAt") == nil)
                .fetchAll(db)
        }
    }
}
