import XCTest
@testable import Gophy
import Foundation

final class MeetingImporterTests: XCTestCase {
    private var tempDir: URL!
    private var storageManager: StorageManager!
    private var database: GophyDatabase!
    private var meetingRepository: MeetingRepository!
    private var documentRepository: DocumentRepository!
    private var vectorSearchService: VectorSearchService!
    private var embeddingPipeline: EmbeddingPipeline!
    private var importer: MeetingImporter!

    override func setUp() async throws {
        try await super.setUp()

        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        storageManager = StorageManager(baseDirectory: tempDir)
        database = try GophyDatabase(storageManager: storageManager)
        meetingRepository = MeetingRepository(database: database)
        documentRepository = DocumentRepository(database: database)
        vectorSearchService = VectorSearchService(database: database)

        let mockEngine = MockImportEmbeddingEngine()
        embeddingPipeline = EmbeddingPipeline(
            embeddingEngine: mockEngine,
            vectorSearchService: vectorSearchService,
            meetingRepository: meetingRepository,
            documentRepository: documentRepository
        )

        importer = MeetingImporter(
            meetingRepository: meetingRepository,
            embeddingPipeline: embeddingPipeline
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    func testImportValidJSONCreatesmeeting() async throws {
        let meeting = ExportedMeetingData(
            id: "import-test-1",
            title: "Imported Meeting",
            startedAt: Date(timeIntervalSince1970: 1000000000),
            endedAt: Date(timeIntervalSince1970: 1000003600),
            mode: "microphone",
            status: "completed",
            createdAt: Date(timeIntervalSince1970: 1000000000)
        )

        let segments = [
            ExportedTranscriptSegment(
                id: "seg-1",
                meetingId: "import-test-1",
                text: "Hello import",
                speaker: "User",
                startTime: 0.0,
                endTime: 2.5,
                createdAt: Date(timeIntervalSince1970: 1000000000)
            ),
            ExportedTranscriptSegment(
                id: "seg-2",
                meetingId: "import-test-1",
                text: "Second segment",
                speaker: "System",
                startTime: 2.5,
                endTime: 5.0,
                createdAt: Date(timeIntervalSince1970: 1000000001)
            )
        ]

        let export = ExportedMeeting(
            version: 1,
            meeting: meeting,
            transcript: segments,
            suggestions: []
        )

        // Write to temp file
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(export)

        let tempFile = tempDir.appendingPathComponent("test.gophy.json")
        try jsonData.write(to: tempFile)

        // Import
        let importedMeeting = try await importer.importMeeting(from: tempFile)

        // Verify meeting was created
        XCTAssertEqual(importedMeeting.id, meeting.id)
        XCTAssertEqual(importedMeeting.title, meeting.title)

        // Verify segments were created
        let importedSegments = try await meetingRepository.getTranscript(meetingId: meeting.id)
        XCTAssertEqual(importedSegments.count, 2)
        XCTAssertEqual(importedSegments[0].text, "Hello import")
        XCTAssertEqual(importedSegments[1].text, "Second segment")
    }

    func testImportInvalidJSONThrowsError() async throws {
        let invalidJSON = "{ invalid json }".data(using: .utf8)!
        let tempFile = tempDir.appendingPathComponent("invalid.gophy.json")
        try invalidJSON.write(to: tempFile)

        do {
            _ = try await importer.importMeeting(from: tempFile)
            XCTFail("Should have thrown an error")
        } catch {
            // Expected error
            XCTAssertTrue(error is DecodingError || error is MeetingImportError)
        }
    }

    func testImportWrongVersionThrowsError() async throws {
        let wrongVersionData: [String: Any] = [
            "version": 99,
            "meeting": [
                "id": "test",
                "title": "Test",
                "startedAt": "2001-09-09T01:46:40Z",
                "mode": "microphone",
                "status": "completed",
                "createdAt": "2001-09-09T01:46:40Z"
            ],
            "transcript": [],
            "suggestions": []
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: wrongVersionData)
        let tempFile = tempDir.appendingPathComponent("wrong-version.gophy.json")
        try jsonData.write(to: tempFile)

        do {
            _ = try await importer.importMeeting(from: tempFile)
            XCTFail("Should have thrown an error")
        } catch MeetingImportError.unsupportedVersion {
            // Expected error
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testImportMissingFileThrowsError() async throws {
        let missingFile = tempDir.appendingPathComponent("nonexistent.gophy.json")

        do {
            _ = try await importer.importMeeting(from: missingFile)
            XCTFail("Should have thrown an error")
        } catch {
            // Expected error
            XCTAssertTrue(error is MeetingImportError || error is CocoaError)
        }
    }
}

// MARK: - Mock Embedding Engine

private final class MockImportEmbeddingEngine: Sendable, EmbeddingProviding {
    func embed(text: String, mode: EmbeddingMode = .passage) async throws -> [Float] {
        return Array(repeating: 0.0, count: 768)
    }

    func embedBatch(texts: [String], mode: EmbeddingMode = .passage) async throws -> [[Float]] {
        return texts.map { _ in Array(repeating: 0.0, count: 768) }
    }
}
