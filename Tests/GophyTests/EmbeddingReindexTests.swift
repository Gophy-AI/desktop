import Testing
import Foundation
import GRDB
@testable import Gophy

@Suite("Embedding Reindex Tests")
struct EmbeddingReindexTests {

    private func makeTestDeps() throws -> (
        storageManager: StorageManager,
        database: GophyDatabase,
        vectorSearchService: VectorSearchService,
        meetingRepository: MeetingRepository,
        documentRepository: DocumentRepository,
        tempDirectory: URL
    ) {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GophyEmbeddingReindexTests-\(UUID().uuidString)")
        let storageManager = StorageManager(baseDirectory: tempDirectory)
        let database = try GophyDatabase(storageManager: storageManager)
        let vectorSearchService = VectorSearchService(database: database)
        let meetingRepository = MeetingRepository(database: database)
        let documentRepository = DocumentRepository(database: database)
        return (storageManager, database, vectorSearchService, meetingRepository, documentRepository, tempDirectory)
    }

    @Test("Migration v10 drops and recreates embedding tables")
    func migrationV10DropsAndRecreatesEmbeddingTables() throws {
        let deps = try makeTestDeps()
        defer { try? FileManager.default.removeItem(at: deps.tempDirectory) }

        let dbQueue = deps.database.dbQueue

        try dbQueue.read { db in
            let appliedMigrations = try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")

            #expect(appliedMigrations.contains("v10_reindex_for_multilingual_e5"), "Should have v10_reindex_for_multilingual_e5 migration")

            let embeddingsExists = try Bool.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='embeddings'"
            ) ?? false
            #expect(embeddingsExists, "embeddings virtual table should exist after migration")

            let mappingExists = try Bool.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='embedding_id_mapping'"
            ) ?? false
            #expect(mappingExists, "embedding_id_mapping table should exist after migration")

            let indexExists = try Bool.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name='idx_embedding_id_mapping_chunk_id'"
            ) ?? false
            #expect(indexExists, "idx_embedding_id_mapping_chunk_id index should exist after migration")
        }
    }

    @Test("After migration embedding count is zero")
    func afterMigrationEmbeddingCountIsZero() async throws {
        let deps = try makeTestDeps()
        defer { try? FileManager.default.removeItem(at: deps.tempDirectory) }

        let count = try await deps.vectorSearchService.count()
        #expect(count == 0, "Embedding count should be 0 after migration v10")
    }

    @Test("Reindex all re-embeds transcript segments and document chunks")
    func reindexAllReembedsTranscriptSegmentsAndDocumentChunks() async throws {
        let deps = try makeTestDeps()
        defer { try? FileManager.default.removeItem(at: deps.tempDirectory) }

        let meetingId = UUID().uuidString
        let meeting = MeetingRecord(
            id: meetingId,
            title: "Test Meeting",
            startedAt: Date(),
            endedAt: Date(),
            mode: "live",
            status: "completed",
            createdAt: Date()
        )
        try await deps.meetingRepository.create(meeting)

        let segment1 = TranscriptSegmentRecord(
            id: UUID().uuidString,
            meetingId: meetingId,
            text: "Hello world",
            speaker: "Speaker 1",
            startTime: 0.0,
            endTime: 2.0,
            createdAt: Date()
        )
        let segment2 = TranscriptSegmentRecord(
            id: UUID().uuidString,
            meetingId: meetingId,
            text: "Second segment",
            speaker: "Speaker 2",
            startTime: 2.0,
            endTime: 4.0,
            createdAt: Date()
        )
        try await deps.meetingRepository.addTranscriptSegment(segment1)
        try await deps.meetingRepository.addTranscriptSegment(segment2)

        let documentId = UUID().uuidString
        let document = DocumentRecord(
            id: documentId,
            name: "test.pdf",
            type: "pdf",
            path: "/path/to/test.pdf",
            status: "ready",
            pageCount: 1,
            createdAt: Date()
        )
        try await deps.documentRepository.create(document)

        let chunk1 = DocumentChunkRecord(
            id: UUID().uuidString,
            documentId: documentId,
            content: "Document content chunk 1",
            chunkIndex: 0,
            pageNumber: 1,
            createdAt: Date()
        )
        let chunk2 = DocumentChunkRecord(
            id: UUID().uuidString,
            documentId: documentId,
            content: "Document content chunk 2",
            chunkIndex: 1,
            pageNumber: 1,
            createdAt: Date()
        )
        try await deps.documentRepository.addChunk(chunk1)
        try await deps.documentRepository.addChunk(chunk2)

        let mockEmbeddingProvider = MockEmbeddingProviderForReindex()
        let embeddingPipeline = EmbeddingPipeline(
            embeddingEngine: mockEmbeddingProvider,
            vectorSearchService: deps.vectorSearchService,
            meetingRepository: deps.meetingRepository,
            documentRepository: deps.documentRepository,
            batchSize: 32
        )

        let reindexService = MockEmbeddingReindexService(
            embeddingPipeline: embeddingPipeline,
            meetingRepository: deps.meetingRepository,
            documentRepository: deps.documentRepository
        )

        var progressCallbacks: [(Int, Int)] = []
        try await reindexService.reindexAll { processed, total in
            progressCallbacks.append((processed, total))
        }

        let finalCount = try await deps.vectorSearchService.count()
        #expect(finalCount == 4, "Should have 4 embeddings after reindex (2 segments + 2 chunks)")

        #expect(!progressCallbacks.isEmpty, "Progress callback should have been called")
        if let lastProgress = progressCallbacks.last {
            #expect(lastProgress.0 == lastProgress.1, "Final progress should show all items processed")
        }
    }

    @Test("After reindex vector count matches segment and chunk count")
    func afterReindexVectorCountMatchesSegmentAndChunkCount() async throws {
        let deps = try makeTestDeps()
        defer { try? FileManager.default.removeItem(at: deps.tempDirectory) }

        let meetingId = UUID().uuidString
        let meeting = MeetingRecord(
            id: meetingId,
            title: "Test Meeting",
            startedAt: Date(),
            endedAt: Date(),
            mode: "live",
            status: "completed",
            createdAt: Date()
        )
        try await deps.meetingRepository.create(meeting)

        try await deps.meetingRepository.addTranscriptSegment(TranscriptSegmentRecord(
            id: UUID().uuidString,
            meetingId: meetingId,
            text: "Segment 1",
            speaker: "Speaker 1",
            startTime: 0.0,
            endTime: 1.0,
            createdAt: Date()
        ))
        try await deps.meetingRepository.addTranscriptSegment(TranscriptSegmentRecord(
            id: UUID().uuidString,
            meetingId: meetingId,
            text: "Segment 2",
            speaker: "Speaker 2",
            startTime: 1.0,
            endTime: 2.0,
            createdAt: Date()
        ))
        try await deps.meetingRepository.addTranscriptSegment(TranscriptSegmentRecord(
            id: UUID().uuidString,
            meetingId: meetingId,
            text: "Segment 3",
            speaker: "Speaker 1",
            startTime: 2.0,
            endTime: 3.0,
            createdAt: Date()
        ))

        let documentId = UUID().uuidString
        let document = DocumentRecord(
            id: documentId,
            name: "test.pdf",
            type: "pdf",
            path: "/path/to/test.pdf",
            status: "ready",
            pageCount: 2,
            createdAt: Date()
        )
        try await deps.documentRepository.create(document)

        try await deps.documentRepository.addChunk(DocumentChunkRecord(
            id: UUID().uuidString,
            documentId: documentId,
            content: "Chunk 1",
            chunkIndex: 0,
            pageNumber: 1,
            createdAt: Date()
        ))
        try await deps.documentRepository.addChunk(DocumentChunkRecord(
            id: UUID().uuidString,
            documentId: documentId,
            content: "Chunk 2",
            chunkIndex: 1,
            pageNumber: 2,
            createdAt: Date()
        ))

        let mockEmbeddingProvider = MockEmbeddingProviderForReindex()
        let embeddingPipeline = EmbeddingPipeline(
            embeddingEngine: mockEmbeddingProvider,
            vectorSearchService: deps.vectorSearchService,
            meetingRepository: deps.meetingRepository,
            documentRepository: deps.documentRepository
        )

        let reindexService = MockEmbeddingReindexService(
            embeddingPipeline: embeddingPipeline,
            meetingRepository: deps.meetingRepository,
            documentRepository: deps.documentRepository
        )

        try await reindexService.reindexAll { _, _ in }

        let vectorCount = try await deps.vectorSearchService.count()
        let segmentCount = try await deps.meetingRepository.getTranscript(meetingId: meetingId).count
        let chunkCount = try await deps.documentRepository.getChunks(documentId: documentId).count

        #expect(vectorCount == segmentCount + chunkCount, "Vector count should match segment + chunk count")
        #expect(vectorCount == 5, "Should have exactly 5 embeddings (3 segments + 2 chunks)")
    }

    @Test("Reindex progress callback fires with correct counts")
    func reindexProgressCallbackFiresWithCorrectCounts() async throws {
        let deps = try makeTestDeps()
        defer { try? FileManager.default.removeItem(at: deps.tempDirectory) }

        let meetingId = UUID().uuidString
        let meeting = MeetingRecord(
            id: meetingId,
            title: "Test Meeting",
            startedAt: Date(),
            endedAt: Date(),
            mode: "live",
            status: "completed",
            createdAt: Date()
        )
        try await deps.meetingRepository.create(meeting)

        for i in 0..<5 {
            try await deps.meetingRepository.addTranscriptSegment(TranscriptSegmentRecord(
                id: UUID().uuidString,
                meetingId: meetingId,
                text: "Segment \(i)",
                speaker: "Speaker",
                startTime: Double(i),
                endTime: Double(i + 1),
                createdAt: Date()
            ))
        }

        let documentId = UUID().uuidString
        let document = DocumentRecord(
            id: documentId,
            name: "test.pdf",
            type: "pdf",
            path: "/path/to/test.pdf",
            status: "ready",
            pageCount: 1,
            createdAt: Date()
        )
        try await deps.documentRepository.create(document)

        for i in 0..<3 {
            try await deps.documentRepository.addChunk(DocumentChunkRecord(
                id: UUID().uuidString,
                documentId: documentId,
                content: "Chunk \(i)",
                chunkIndex: i,
                pageNumber: 1,
                createdAt: Date()
            ))
        }

        let mockEmbeddingProvider = MockEmbeddingProviderForReindex()
        let embeddingPipeline = EmbeddingPipeline(
            embeddingEngine: mockEmbeddingProvider,
            vectorSearchService: deps.vectorSearchService,
            meetingRepository: deps.meetingRepository,
            documentRepository: deps.documentRepository
        )

        let reindexService = MockEmbeddingReindexService(
            embeddingPipeline: embeddingPipeline,
            meetingRepository: deps.meetingRepository,
            documentRepository: deps.documentRepository
        )

        var progressCallbacks: [(Int, Int)] = []
        try await reindexService.reindexAll { processed, total in
            progressCallbacks.append((processed, total))
        }

        #expect(!progressCallbacks.isEmpty, "Progress callback should have been called at least once")

        for (processed, total) in progressCallbacks {
            #expect(processed >= 0, "Processed count should be non-negative")
            #expect(processed <= total, "Processed count should not exceed total")
            #expect(total == 8, "Total should be 8 (5 segments + 3 chunks)")
        }

        if let lastProgress = progressCallbacks.last {
            #expect(lastProgress.0 == 8, "Final processed count should be 8")
            #expect(lastProgress.1 == 8, "Final total count should be 8")
        }
    }
}

private final class MockEmbeddingProviderForReindex: EmbeddingProviding {
    func embed(text: String, mode: EmbeddingMode) async throws -> [Float] {
        return [Float](repeating: 0.1, count: 384)
    }

    func embedBatch(texts: [String], mode: EmbeddingMode) async throws -> [[Float]] {
        return texts.map { _ in [Float](repeating: 0.1, count: 384) }
    }
}

private final class MockEmbeddingReindexService: Sendable {
    private let embeddingPipeline: EmbeddingPipeline
    private let meetingRepository: MeetingRepository
    private let documentRepository: DocumentRepository

    init(
        embeddingPipeline: EmbeddingPipeline,
        meetingRepository: MeetingRepository,
        documentRepository: DocumentRepository
    ) {
        self.embeddingPipeline = embeddingPipeline
        self.meetingRepository = meetingRepository
        self.documentRepository = documentRepository
    }

    func needsReindex() async -> Bool {
        return true
    }

    func reindexAll(progress: @escaping (Int, Int) -> Void) async throws {
        let allMeetings = try await meetingRepository.listAll()
        let allDocuments = try await documentRepository.listAll()

        var allSegments: [TranscriptSegmentRecord] = []
        for meeting in allMeetings {
            let segments = try await meetingRepository.getTranscript(meetingId: meeting.id)
            allSegments.append(contentsOf: segments)
        }

        var allChunks: [DocumentChunkRecord] = []
        for document in allDocuments {
            let chunks = try await documentRepository.getChunks(documentId: document.id)
            allChunks.append(contentsOf: chunks)
        }

        let total = allSegments.count + allChunks.count
        var processed = 0

        for segment in allSegments {
            try await embeddingPipeline.indexTranscriptSegment(segment: segment)
            processed += 1
            progress(processed, total)
        }

        for chunk in allChunks {
            try await embeddingPipeline.indexDocumentChunk(chunk: chunk)
            processed += 1
            progress(processed, total)
        }
    }
}
