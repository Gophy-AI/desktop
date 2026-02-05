import XCTest
import Foundation
import GRDB
@testable import Gophy

final class DatabaseTests: XCTestCase {
    var tempDirectory: URL!
    var storageManager: StorageManager!
    var database: GophyDatabase!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GophyDBTests-\(UUID().uuidString)")
        storageManager = StorageManager(baseDirectory: tempDirectory)
        database = try GophyDatabase(storageManager: storageManager)
    }

    override func tearDown() async throws {
        database = nil
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    func testFreshDatabaseRunsAllMigrations() throws {
        let dbQueue = try database.dbQueue

        try dbQueue.read { db in
            let appliedMigrations = try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")

            XCTAssertEqual(appliedMigrations.count, 7, "Should have 7 migrations applied")
            XCTAssertTrue(appliedMigrations.contains("v1_create_meetings"), "Should have meetings migration")
            XCTAssertTrue(appliedMigrations.contains("v2_create_transcript_segments"), "Should have transcript_segments migration")
            XCTAssertTrue(appliedMigrations.contains("v3_create_documents"), "Should have documents migration")
            XCTAssertTrue(appliedMigrations.contains("v4_create_document_chunks"), "Should have document_chunks migration")
            XCTAssertTrue(appliedMigrations.contains("v5_create_chat_messages"), "Should have chat_messages migration")
            XCTAssertTrue(appliedMigrations.contains("v6_create_settings"), "Should have settings migration")
            XCTAssertTrue(appliedMigrations.contains("v7_create_embeddings"), "Should have embeddings migration")
        }
    }

    func testWALModeEnabled() throws {
        let dbQueue = try database.dbQueue

        try dbQueue.read { db in
            let journalMode = try String.fetchOne(db, sql: "PRAGMA journal_mode")
            XCTAssertEqual(journalMode, "wal", "Database should be in WAL mode")
        }
    }

    func testInsertAndFetchMeeting() throws {
        let dbQueue = try database.dbQueue

        let meeting = MeetingRecord(
            id: UUID().uuidString,
            title: "Test Meeting",
            startedAt: Date(),
            endedAt: nil,
            mode: "live",
            status: "active",
            createdAt: Date()
        )

        try dbQueue.write { db in
            try meeting.insert(db)
        }

        let fetched = try dbQueue.read { db in
            try MeetingRecord.fetchOne(db, key: meeting.id)
        }

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, meeting.id)
        XCTAssertEqual(fetched?.title, meeting.title)
        XCTAssertEqual(fetched?.mode, meeting.mode)
        XCTAssertEqual(fetched?.status, meeting.status)
    }

    func testInsertAndFetchTranscriptSegment() throws {
        let dbQueue = try database.dbQueue

        let meetingId = UUID().uuidString
        let meeting = MeetingRecord(
            id: meetingId,
            title: "Test Meeting",
            startedAt: Date(),
            endedAt: nil,
            mode: "live",
            status: "active",
            createdAt: Date()
        )

        let segment = TranscriptSegmentRecord(
            id: UUID().uuidString,
            meetingId: meetingId,
            text: "Hello world",
            speaker: "Speaker 1",
            startTime: 0.0,
            endTime: 2.5,
            createdAt: Date()
        )

        try dbQueue.write { db in
            try meeting.insert(db)
            try segment.insert(db)
        }

        let fetched = try dbQueue.read { db in
            try TranscriptSegmentRecord.fetchOne(db, key: segment.id)
        }

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, segment.id)
        XCTAssertEqual(fetched?.meetingId, segment.meetingId)
        XCTAssertEqual(fetched?.text, segment.text)
        XCTAssertEqual(fetched?.speaker, segment.speaker)
        XCTAssertEqual(fetched?.startTime, segment.startTime)
        XCTAssertEqual(fetched?.endTime, segment.endTime)
    }

    func testInsertAndFetchDocument() throws {
        let dbQueue = try database.dbQueue

        let document = DocumentRecord(
            id: UUID().uuidString,
            name: "test.pdf",
            type: "pdf",
            path: "/path/to/test.pdf",
            status: "ready",
            pageCount: 10,
            createdAt: Date()
        )

        try dbQueue.write { db in
            try document.insert(db)
        }

        let fetched = try dbQueue.read { db in
            try DocumentRecord.fetchOne(db, key: document.id)
        }

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, document.id)
        XCTAssertEqual(fetched?.name, document.name)
        XCTAssertEqual(fetched?.type, document.type)
        XCTAssertEqual(fetched?.path, document.path)
        XCTAssertEqual(fetched?.status, document.status)
        XCTAssertEqual(fetched?.pageCount, document.pageCount)
    }

    func testInsertAndFetchDocumentChunk() throws {
        let dbQueue = try database.dbQueue

        let documentId = UUID().uuidString
        let document = DocumentRecord(
            id: documentId,
            name: "test.pdf",
            type: "pdf",
            path: "/path/to/test.pdf",
            status: "ready",
            pageCount: 10,
            createdAt: Date()
        )

        let chunk = DocumentChunkRecord(
            id: UUID().uuidString,
            documentId: documentId,
            content: "This is a chunk of text",
            chunkIndex: 0,
            pageNumber: 1,
            createdAt: Date()
        )

        try dbQueue.write { db in
            try document.insert(db)
            try chunk.insert(db)
        }

        let fetched = try dbQueue.read { db in
            try DocumentChunkRecord.fetchOne(db, key: chunk.id)
        }

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, chunk.id)
        XCTAssertEqual(fetched?.documentId, chunk.documentId)
        XCTAssertEqual(fetched?.content, chunk.content)
        XCTAssertEqual(fetched?.chunkIndex, chunk.chunkIndex)
        XCTAssertEqual(fetched?.pageNumber, chunk.pageNumber)
    }

    func testInsertAndFetchChatMessage() throws {
        let dbQueue = try database.dbQueue

        let message = ChatMessageRecord(
            id: UUID().uuidString,
            role: "user",
            content: "Hello, assistant",
            meetingId: nil,
            createdAt: Date()
        )

        try dbQueue.write { db in
            try message.insert(db)
        }

        let fetched = try dbQueue.read { db in
            try ChatMessageRecord.fetchOne(db, key: message.id)
        }

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, message.id)
        XCTAssertEqual(fetched?.role, message.role)
        XCTAssertEqual(fetched?.content, message.content)
        XCTAssertNil(fetched?.meetingId)
    }

    func testInsertAndFetchChatMessageWithMeeting() throws {
        let dbQueue = try database.dbQueue

        let meetingId = UUID().uuidString
        let meeting = MeetingRecord(
            id: meetingId,
            title: "Test Meeting",
            startedAt: Date(),
            endedAt: nil,
            mode: "live",
            status: "active",
            createdAt: Date()
        )

        let message = ChatMessageRecord(
            id: UUID().uuidString,
            role: "assistant",
            content: "I can help with that",
            meetingId: meetingId,
            createdAt: Date()
        )

        try dbQueue.write { db in
            try meeting.insert(db)
            try message.insert(db)
        }

        let fetched = try dbQueue.read { db in
            try ChatMessageRecord.fetchOne(db, key: message.id)
        }

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.meetingId, meetingId)
    }

    func testInsertAndFetchSettings() throws {
        let dbQueue = try database.dbQueue

        let setting = SettingRecord(key: "theme", value: "dark")

        try dbQueue.write { db in
            try setting.insert(db)
        }

        let fetched = try dbQueue.read { db in
            try SettingRecord.fetchOne(db, key: setting.key)
        }

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.key, setting.key)
        XCTAssertEqual(fetched?.value, setting.value)
    }

    func testSQLiteVecVirtualTableRespondsToQueries() throws {
        let dbQueue = try database.dbQueue

        try dbQueue.write { db in
            let embedding = [Float](repeating: 0.5, count: 768)
            let blob = Data(bytes: embedding, count: embedding.count * MemoryLayout<Float>.size)

            try db.execute(
                sql: "INSERT INTO embeddings(rowid, embedding) VALUES (?, ?)",
                arguments: [1, blob]
            )
        }

        let count = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM embeddings")
        }

        XCTAssertEqual(count, 1, "Should have one embedding row")

        let exists = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM embeddings WHERE rowid = 1")
        }

        XCTAssertEqual(exists, 1, "Should be able to query by rowid")
    }

    func testRunningMigrationsTwiceDoesNotError() throws {
        let firstDB = try GophyDatabase(storageManager: storageManager)
        let firstDBQueue = try firstDB.dbQueue

        let firstCount = try firstDBQueue.read { db in
            try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations").count
        }

        XCTAssertEqual(firstCount, 7, "First database should have 7 migrations")

        let secondDB = try GophyDatabase(storageManager: storageManager)
        let secondDBQueue = try secondDB.dbQueue

        let secondCount = try secondDBQueue.read { db in
            try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations").count
        }

        XCTAssertEqual(secondCount, 7, "Second database should still have 7 migrations")
    }
}
