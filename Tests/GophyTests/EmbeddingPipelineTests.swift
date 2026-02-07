import XCTest
import Foundation
import GRDB
@testable import Gophy

final class MockEmbeddingProvider: EmbeddingProviding, @unchecked Sendable {
    var isLoaded: Bool = true
    var embedCallCount = 0
    var embedBatchCallCount = 0

    func embed(text: String, mode: EmbeddingMode = .passage) async throws -> [Float] {
        embedCallCount += 1
        return deterministicEmbedding(for: text)
    }

    func embedBatch(texts: [String], mode: EmbeddingMode = .passage) async throws -> [[Float]] {
        embedBatchCallCount += 1
        return texts.map { deterministicEmbedding(for: $0) }
    }

    private func deterministicEmbedding(for text: String) -> [Float] {
        let hash = text.hashValue
        var embedding = [Float](repeating: 0.0, count: 768)
        for i in 0..<768 {
            embedding[i] = Float((hash &+ i) % 100) / 100.0
        }
        return embedding
    }
}

final class EmbeddingPipelineTests: XCTestCase {
    var tempDirectory: URL!
    var storageManager: StorageManager!
    var database: GophyDatabase!
    var vectorSearchService: VectorSearchService!
    var meetingRepository: MeetingRepository!
    var documentRepository: DocumentRepository!
    var mockEmbeddingProvider: MockEmbeddingProvider!
    var pipeline: EmbeddingPipeline!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GophyEmbeddingPipelineTests-\(UUID().uuidString)")
        storageManager = StorageManager(baseDirectory: tempDirectory)
        database = try GophyDatabase(storageManager: storageManager)
        vectorSearchService = VectorSearchService(database: database)
        meetingRepository = MeetingRepository(database: database)
        documentRepository = DocumentRepository(database: database)
        mockEmbeddingProvider = MockEmbeddingProvider()
        pipeline = EmbeddingPipeline(
            embeddingEngine: mockEmbeddingProvider,
            vectorSearchService: vectorSearchService,
            meetingRepository: meetingRepository,
            documentRepository: documentRepository
        )
    }

    override func tearDown() async throws {
        pipeline = nil
        mockEmbeddingProvider = nil
        documentRepository = nil
        meetingRepository = nil
        vectorSearchService = nil
        database = nil
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }

    func testIndexTranscriptSegmentCreatesVectorInSQLiteVec() async throws {
        let segment = TranscriptSegmentRecord(
            id: "segment-1",
            meetingId: "meeting-1",
            text: "This is a test transcript segment",
            speaker: "Speaker A",
            startTime: 0.0,
            endTime: 5.0,
            createdAt: Date()
        )

        try await pipeline.indexTranscriptSegment(segment: segment)

        let count = try await vectorSearchService.count()
        XCTAssertEqual(count, 1, "Should have one embedding in vector search")

        let queryEmbedding = try await mockEmbeddingProvider.embed(text: segment.text)
        let results = try await vectorSearchService.search(query: queryEmbedding, limit: 1)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].id, segment.id)
        XCTAssertEqual(results[0].distance, 0.0, accuracy: 0.001, "Identical embedding should have distance 0")
    }

    func testIndexMeetingIndexesAllSegments() async throws {
        let meeting = MeetingRecord(
            id: "meeting-1",
            title: "Test Meeting",
            startedAt: Date(),
            endedAt: nil,
            mode: "microphone",
            status: "completed",
            createdAt: Date()
        )
        try await meetingRepository.create(meeting)

        let segments = [
            TranscriptSegmentRecord(
                id: "segment-1",
                meetingId: meeting.id,
                text: "First segment",
                speaker: "Speaker A",
                startTime: 0.0,
                endTime: 5.0,
                createdAt: Date()
            ),
            TranscriptSegmentRecord(
                id: "segment-2",
                meetingId: meeting.id,
                text: "Second segment",
                speaker: "Speaker B",
                startTime: 5.0,
                endTime: 10.0,
                createdAt: Date()
            ),
            TranscriptSegmentRecord(
                id: "segment-3",
                meetingId: meeting.id,
                text: "Third segment",
                speaker: "Speaker A",
                startTime: 10.0,
                endTime: 15.0,
                createdAt: Date()
            )
        ]

        for segment in segments {
            try await meetingRepository.addTranscriptSegment(segment)
        }

        try await pipeline.indexMeeting(meetingId: meeting.id)

        let count = try await vectorSearchService.count()
        XCTAssertEqual(count, 3, "Should have indexed all 3 segments")

        for segment in segments {
            let queryEmbedding = try await mockEmbeddingProvider.embed(text: segment.text)
            let results = try await vectorSearchService.search(query: queryEmbedding, limit: 1)
            XCTAssertEqual(results[0].id, segment.id, "Should find segment \(segment.id)")
        }
    }

    func testIndexDocumentIndexesAllChunks() async throws {
        let document = DocumentRecord(
            id: "doc-1",
            name: "Test Document",
            type: "pdf",
            path: "/path/to/doc.pdf",
            status: "ready",
            pageCount: 1,
            createdAt: Date()
        )
        try await documentRepository.create(document)

        let chunks = [
            DocumentChunkRecord(
                id: "chunk-1",
                documentId: document.id,
                content: "First chunk content",
                chunkIndex: 0,
                pageNumber: 1,
                createdAt: Date()
            ),
            DocumentChunkRecord(
                id: "chunk-2",
                documentId: document.id,
                content: "Second chunk content",
                chunkIndex: 1,
                pageNumber: 1,
                createdAt: Date()
            ),
            DocumentChunkRecord(
                id: "chunk-3",
                documentId: document.id,
                content: "Third chunk content",
                chunkIndex: 2,
                pageNumber: 1,
                createdAt: Date()
            )
        ]

        for chunk in chunks {
            try await documentRepository.addChunk(chunk)
        }

        try await pipeline.indexDocument(documentId: document.id)

        let count = try await vectorSearchService.count()
        XCTAssertEqual(count, 3, "Should have indexed all 3 chunks")

        for chunk in chunks {
            let queryEmbedding = try await mockEmbeddingProvider.embed(text: chunk.content)
            let results = try await vectorSearchService.search(query: queryEmbedding, limit: 1)
            XCTAssertEqual(results[0].id, chunk.id, "Should find chunk \(chunk.id)")
        }
    }

    func testReIndexingUpdatesNotDuplicates() async throws {
        let segment = TranscriptSegmentRecord(
            id: "segment-1",
            meetingId: "meeting-1",
            text: "Initial text",
            speaker: "Speaker A",
            startTime: 0.0,
            endTime: 5.0,
            createdAt: Date()
        )

        try await pipeline.indexTranscriptSegment(segment: segment)

        var count = try await vectorSearchService.count()
        XCTAssertEqual(count, 1)

        let updatedSegment = TranscriptSegmentRecord(
            id: segment.id,
            meetingId: segment.meetingId,
            text: "Updated text with different content",
            speaker: segment.speaker,
            startTime: segment.startTime,
            endTime: segment.endTime,
            createdAt: segment.createdAt
        )

        try await pipeline.indexTranscriptSegment(segment: updatedSegment)

        count = try await vectorSearchService.count()
        XCTAssertEqual(count, 1, "Re-indexing should update, not create duplicate")

        let queryEmbedding = try await mockEmbeddingProvider.embed(text: updatedSegment.text)
        let results = try await vectorSearchService.search(query: queryEmbedding, limit: 1)
        XCTAssertEqual(results[0].id, segment.id)
        XCTAssertEqual(results[0].distance, 0.0, accuracy: 0.001, "Should match updated embedding")
    }

    func testSearchAfterIndexingReturnsRelevantResults() async throws {
        let meeting = MeetingRecord(
            id: "meeting-1",
            title: "Test Meeting",
            startedAt: Date(),
            endedAt: nil,
            mode: "microphone",
            status: "completed",
            createdAt: Date()
        )
        try await meetingRepository.create(meeting)

        let segments = [
            TranscriptSegmentRecord(
                id: "segment-1",
                meetingId: meeting.id,
                text: "Discussion about machine learning and AI",
                speaker: "Speaker A",
                startTime: 0.0,
                endTime: 5.0,
                createdAt: Date()
            ),
            TranscriptSegmentRecord(
                id: "segment-2",
                meetingId: meeting.id,
                text: "Budget allocation for next quarter",
                speaker: "Speaker B",
                startTime: 5.0,
                endTime: 10.0,
                createdAt: Date()
            ),
            TranscriptSegmentRecord(
                id: "segment-3",
                meetingId: meeting.id,
                text: "Deep learning models and neural networks",
                speaker: "Speaker A",
                startTime: 10.0,
                endTime: 15.0,
                createdAt: Date()
            )
        ]

        for segment in segments {
            try await meetingRepository.addTranscriptSegment(segment)
        }

        try await pipeline.indexMeeting(meetingId: meeting.id)

        let searchQuery = "machine learning and AI"
        let queryEmbedding = try await mockEmbeddingProvider.embed(text: searchQuery)
        let results = try await vectorSearchService.search(query: queryEmbedding, limit: 2)

        XCTAssertEqual(results.count, 2, "Should return requested number of results")
        let resultIds = results.map { $0.id }
        XCTAssertTrue(resultIds.contains("segment-1") || resultIds.contains("segment-2") || resultIds.contains("segment-3"),
                      "Search should return indexed segments")
    }

    func testIndexDocumentChunkStoresVector() async throws {
        let chunk = DocumentChunkRecord(
            id: "chunk-1",
            documentId: "doc-1",
            content: "This is a document chunk",
            chunkIndex: 0,
            pageNumber: 1,
            createdAt: Date()
        )

        try await pipeline.indexDocumentChunk(chunk: chunk)

        let count = try await vectorSearchService.count()
        XCTAssertEqual(count, 1)

        let queryEmbedding = try await mockEmbeddingProvider.embed(text: chunk.content)
        let results = try await vectorSearchService.search(query: queryEmbedding, limit: 1)
        XCTAssertEqual(results[0].id, chunk.id)
    }

    func testBatchProcessingUsedForLargeCollections() async throws {
        let document = DocumentRecord(
            id: "doc-1",
            name: "Large Document",
            type: "pdf",
            path: "/path/to/large.pdf",
            status: "ready",
            pageCount: 10,
            createdAt: Date()
        )
        try await documentRepository.create(document)

        let chunkCount = 50
        for i in 0..<chunkCount {
            let chunk = DocumentChunkRecord(
                id: "chunk-\(i)",
                documentId: document.id,
                content: "Chunk content number \(i)",
                chunkIndex: i,
                pageNumber: (i / 5) + 1,
                createdAt: Date()
            )
            try await documentRepository.addChunk(chunk)
        }

        let initialBatchCallCount = mockEmbeddingProvider.embedBatchCallCount

        try await pipeline.indexDocument(documentId: document.id)

        XCTAssertGreaterThan(mockEmbeddingProvider.embedBatchCallCount, initialBatchCallCount,
                             "Should use batch processing for multiple chunks")

        let count = try await vectorSearchService.count()
        XCTAssertEqual(count, chunkCount, "All chunks should be indexed")
    }
}
