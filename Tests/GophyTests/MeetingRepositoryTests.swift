import XCTest
import Foundation
import GRDB
@testable import Gophy

final class MeetingRepositoryTests: XCTestCase {
    var tempDirectory: URL!
    var storageManager: StorageManager!
    var database: GophyDatabase!
    var repository: MeetingRepository!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GophyMeetingRepoTests-\(UUID().uuidString)")
        storageManager = StorageManager(baseDirectory: tempDirectory)
        database = try GophyDatabase(storageManager: storageManager)
        repository = MeetingRepository(database: database)
    }

    override func tearDown() async throws {
        repository = nil
        database = nil
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    func testCreateMeetingAndFetchById() async throws {
        let meeting = MeetingRecord(
            id: UUID().uuidString,
            title: "Test Meeting",
            startedAt: Date(),
            endedAt: nil,
            mode: "live",
            status: "active",
            createdAt: Date()
        )

        try await repository.create(meeting)

        let fetched = try await repository.get(id: meeting.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, meeting.id)
        XCTAssertEqual(fetched?.title, meeting.title)
        XCTAssertEqual(fetched?.mode, meeting.mode)
        XCTAssertEqual(fetched?.status, meeting.status)
    }

    func testGetNonExistentMeetingReturnsNil() async throws {
        let fetched = try await repository.get(id: "non-existent-id")
        XCTAssertNil(fetched)
    }

    func testAddTranscriptSegmentsAndFetchOrdered() async throws {
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

        try await repository.create(meeting)

        let segment1 = TranscriptSegmentRecord(
            id: UUID().uuidString,
            meetingId: meetingId,
            text: "Hello",
            speaker: "Speaker 1",
            startTime: 1.0,
            endTime: 2.0,
            createdAt: Date()
        )

        let segment2 = TranscriptSegmentRecord(
            id: UUID().uuidString,
            meetingId: meetingId,
            text: "World",
            speaker: "Speaker 2",
            startTime: 0.0,
            endTime: 0.5,
            createdAt: Date()
        )

        let segment3 = TranscriptSegmentRecord(
            id: UUID().uuidString,
            meetingId: meetingId,
            text: "Goodbye",
            speaker: "Speaker 1",
            startTime: 2.5,
            endTime: 3.0,
            createdAt: Date()
        )

        try await repository.addTranscriptSegment(segment1)
        try await repository.addTranscriptSegment(segment2)
        try await repository.addTranscriptSegment(segment3)

        let transcript = try await repository.getTranscript(meetingId: meetingId)
        XCTAssertEqual(transcript.count, 3)
        XCTAssertEqual(transcript[0].text, "World", "Segments should be ordered by startTime")
        XCTAssertEqual(transcript[1].text, "Hello")
        XCTAssertEqual(transcript[2].text, "Goodbye")
    }

    func testListAllWithPagination() async throws {
        let now = Date()
        let meeting1 = MeetingRecord(
            id: UUID().uuidString,
            title: "Meeting 1",
            startedAt: now.addingTimeInterval(-3600),
            endedAt: nil,
            mode: "live",
            status: "active",
            createdAt: now.addingTimeInterval(-3600)
        )
        let meeting2 = MeetingRecord(
            id: UUID().uuidString,
            title: "Meeting 2",
            startedAt: now.addingTimeInterval(-1800),
            endedAt: nil,
            mode: "live",
            status: "active",
            createdAt: now.addingTimeInterval(-1800)
        )
        let meeting3 = MeetingRecord(
            id: UUID().uuidString,
            title: "Meeting 3",
            startedAt: now,
            endedAt: nil,
            mode: "live",
            status: "active",
            createdAt: now
        )

        try await repository.create(meeting1)
        try await repository.create(meeting2)
        try await repository.create(meeting3)

        let page1 = try await repository.listAll(limit: 2, offset: 0)
        XCTAssertEqual(page1.count, 2)
        XCTAssertEqual(page1[0].title, "Meeting 3", "Should be ordered by startedAt DESC")
        XCTAssertEqual(page1[1].title, "Meeting 2")

        let page2 = try await repository.listAll(limit: 2, offset: 2)
        XCTAssertEqual(page2.count, 1)
        XCTAssertEqual(page2[0].title, "Meeting 1")

        let all = try await repository.listAll()
        XCTAssertEqual(all.count, 3)
    }

    func testDeleteCascadesToTranscriptSegments() async throws {
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

        try await repository.create(meeting)

        let segment = TranscriptSegmentRecord(
            id: UUID().uuidString,
            meetingId: meetingId,
            text: "Test segment",
            speaker: "Speaker 1",
            startTime: 0.0,
            endTime: 1.0,
            createdAt: Date()
        )

        try await repository.addTranscriptSegment(segment)

        let transcriptBeforeDelete = try await repository.getTranscript(meetingId: meetingId)
        XCTAssertEqual(transcriptBeforeDelete.count, 1)

        try await repository.delete(id: meetingId)

        let meetingAfterDelete = try await repository.get(id: meetingId)
        XCTAssertNil(meetingAfterDelete)

        let transcriptAfterDelete = try await repository.getTranscript(meetingId: meetingId)
        XCTAssertEqual(transcriptAfterDelete.count, 0, "Transcript segments should be deleted with meeting")
    }

    func testSearchByTranscriptContent() async throws {
        let meeting1Id = UUID().uuidString
        let meeting1 = MeetingRecord(
            id: meeting1Id,
            title: "Meeting 1",
            startedAt: Date(),
            endedAt: nil,
            mode: "live",
            status: "active",
            createdAt: Date()
        )

        let meeting2Id = UUID().uuidString
        let meeting2 = MeetingRecord(
            id: meeting2Id,
            title: "Meeting 2",
            startedAt: Date(),
            endedAt: nil,
            mode: "live",
            status: "active",
            createdAt: Date()
        )

        try await repository.create(meeting1)
        try await repository.create(meeting2)

        let segment1 = TranscriptSegmentRecord(
            id: UUID().uuidString,
            meetingId: meeting1Id,
            text: "Discuss quarterly revenue projections",
            speaker: "Speaker 1",
            startTime: 0.0,
            endTime: 1.0,
            createdAt: Date()
        )

        let segment2 = TranscriptSegmentRecord(
            id: UUID().uuidString,
            meetingId: meeting2Id,
            text: "Review customer feedback survey",
            speaker: "Speaker 2",
            startTime: 0.0,
            endTime: 1.0,
            createdAt: Date()
        )

        try await repository.addTranscriptSegment(segment1)
        try await repository.addTranscriptSegment(segment2)

        let results = try await repository.search(query: "revenue")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, meeting1Id)

        let noResults = try await repository.search(query: "nonexistent")
        XCTAssertEqual(noResults.count, 0)
    }

    func testUpdateMeeting() async throws {
        let meeting = MeetingRecord(
            id: UUID().uuidString,
            title: "Original Title",
            startedAt: Date(),
            endedAt: nil,
            mode: "live",
            status: "active",
            createdAt: Date()
        )

        try await repository.create(meeting)

        let endedAt = Date()
        let updatedMeeting = MeetingRecord(
            id: meeting.id,
            title: "Updated Title",
            startedAt: meeting.startedAt,
            endedAt: endedAt,
            mode: meeting.mode,
            status: "completed",
            createdAt: meeting.createdAt
        )

        try await repository.update(updatedMeeting)

        let fetched = try await repository.get(id: meeting.id)
        XCTAssertEqual(fetched?.title, "Updated Title")
        XCTAssertEqual(fetched?.status, "completed")
        XCTAssertNotNil(fetched?.endedAt)
    }
}
