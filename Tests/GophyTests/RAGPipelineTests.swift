import XCTest
@testable import Gophy

final class RAGPipelineTests: XCTestCase {
    var embeddingEngine: MockEmbeddingEngineForRAG!
    var vectorSearchService: MockVectorSearchServiceForRAG!
    var textGenerationEngine: MockTextGenerationEngineForRAG!
    var meetingRepository: MockMeetingRepositoryForRAG!
    var documentRepository: MockDocumentRepositoryForRAG!
    var pipeline: RAGPipeline!

    override func setUp() async throws {
        embeddingEngine = MockEmbeddingEngineForRAG()
        vectorSearchService = MockVectorSearchServiceForRAG()
        textGenerationEngine = MockTextGenerationEngineForRAG()
        meetingRepository = MockMeetingRepositoryForRAG()
        documentRepository = MockDocumentRepositoryForRAG()

        pipeline = RAGPipeline(
            embeddingEngine: embeddingEngine,
            vectorSearchService: vectorSearchService,
            textGenerationEngine: textGenerationEngine,
            meetingRepository: meetingRepository,
            documentRepository: documentRepository,
            topK: 10
        )
    }

    func testQueryReturnsRelevantContextFromMeetings() async throws {
        let segmentId = UUID().uuidString
        let segment = TranscriptSegmentRecord(
            id: segmentId,
            meetingId: "meeting-1",
            text: "Discuss project timeline and deliverables",
            speaker: "Alice",
            startTime: 0.0,
            endTime: 5.0,
            createdAt: Date()
        )

        meetingRepository.segments[segmentId] = segment

        embeddingEngine.embedResult = Array(repeating: 0.5, count: 768)

        vectorSearchService.searchResults = [
            VectorSearchResult(id: segmentId, distance: 0.1)
        ]

        textGenerationEngine.generatedTokens = ["Answer", " based", " on", " context"]

        var tokens: [String] = []
        let stream = pipeline.query(question: "What was discussed?", scope: .all)

        for await token in stream {
            tokens.append(token)
        }

        XCTAssertEqual(tokens, ["Answer", " based", " on", " context"])
        XCTAssertEqual(embeddingEngine.embedCallCount, 1)
        XCTAssertEqual(embeddingEngine.lastEmbedText, "What was discussed?")
        XCTAssertEqual(vectorSearchService.searchCallCount, 1)
        XCTAssertEqual(textGenerationEngine.generateCallCount, 1)
        XCTAssertTrue(textGenerationEngine.lastSystemPrompt?.contains("Discuss project timeline and deliverables") ?? false)
    }

    func testQueryScopedToDocumentsOnlySearchesDocuments() async throws {
        let segmentId = UUID().uuidString
        let chunkId = UUID().uuidString

        let segment = TranscriptSegmentRecord(
            id: segmentId,
            meetingId: "meeting-1",
            text: "Meeting text",
            speaker: "Bob",
            startTime: 0.0,
            endTime: 5.0,
            createdAt: Date()
        )

        let chunk = DocumentChunkRecord(
            id: chunkId,
            documentId: "doc-1",
            content: "Document content about AI",
            chunkIndex: 0,
            pageNumber: 1,
            createdAt: Date()
        )

        meetingRepository.segments[segmentId] = segment
        documentRepository.chunks[chunkId] = chunk

        embeddingEngine.embedResult = Array(repeating: 0.5, count: 768)

        vectorSearchService.searchResults = [
            VectorSearchResult(id: segmentId, distance: 0.1),
            VectorSearchResult(id: chunkId, distance: 0.2)
        ]

        textGenerationEngine.generatedTokens = ["Answer"]

        var tokens: [String] = []
        let stream = pipeline.query(question: "Tell me about AI", scope: .documents)

        for await token in stream {
            tokens.append(token)
        }

        XCTAssertEqual(tokens, ["Answer"])
        XCTAssertTrue(textGenerationEngine.lastSystemPrompt?.contains("Document content about AI") ?? false)
        XCTAssertFalse(textGenerationEngine.lastSystemPrompt?.contains("Meeting text") ?? false)
    }

    func testStreamingResponseEmitsTokens() async throws {
        let chunkId = UUID().uuidString
        let chunk = DocumentChunkRecord(
            id: chunkId,
            documentId: "doc-1",
            content: "Test content",
            chunkIndex: 0,
            pageNumber: 1,
            createdAt: Date()
        )

        documentRepository.chunks[chunkId] = chunk

        embeddingEngine.embedResult = Array(repeating: 0.5, count: 768)

        vectorSearchService.searchResults = [
            VectorSearchResult(id: chunkId, distance: 0.1)
        ]

        textGenerationEngine.generatedTokens = ["Hello", " world", "!"]

        var tokens: [String] = []
        let stream = pipeline.query(question: "Test question", scope: .all)

        for await token in stream {
            tokens.append(token)
        }

        XCTAssertEqual(tokens.count, 3)
        XCTAssertEqual(tokens, ["Hello", " world", "!"])
    }
}

final class MockEmbeddingEngineForRAG: EmbeddingProviding, @unchecked Sendable {
    var embedResult: [Float] = []
    var embedCallCount = 0
    var lastEmbedText: String?
    var lastEmbedMode: EmbeddingMode?

    func embed(text: String, mode: EmbeddingMode = .passage) async throws -> [Float] {
        embedCallCount += 1
        lastEmbedText = text
        lastEmbedMode = mode
        return embedResult
    }

    func embedBatch(texts: [String], mode: EmbeddingMode = .passage) async throws -> [[Float]] {
        var results: [[Float]] = []
        for text in texts {
            results.append(try await embed(text: text, mode: mode))
        }
        return results
    }
}

final class MockVectorSearchServiceForRAG: VectorSearching, @unchecked Sendable {
    var searchResults: [VectorSearchResult] = []
    var searchCallCount = 0

    func search(query: [Float], limit: Int) async throws -> [VectorSearchResult] {
        searchCallCount += 1
        return searchResults
    }
}

final class MockTextGenerationEngineForRAG: TextGenerationProviding, @unchecked Sendable {
    var generatedTokens: [String] = []
    var generateCallCount = 0
    var lastPrompt: String?
    var lastSystemPrompt: String?

    func generate(prompt: String, systemPrompt: String, maxTokens: Int) -> AsyncStream<String> {
        generateCallCount += 1
        lastPrompt = prompt
        lastSystemPrompt = systemPrompt

        return AsyncStream { continuation in
            for token in generatedTokens {
                continuation.yield(token)
            }
            continuation.finish()
        }
    }
}

final class MockMeetingRepositoryForRAG: MeetingRepositoryProtocol, @unchecked Sendable {
    var segments: [String: TranscriptSegmentRecord] = [:]

    func create(_ meeting: MeetingRecord) async throws {}
    func update(_ meeting: MeetingRecord) async throws {}
    func get(id: String) async throws -> MeetingRecord? { nil }
    func listAll(limit: Int? = nil, offset: Int = 0) async throws -> [MeetingRecord] { [] }
    func delete(id: String) async throws {}
    func addTranscriptSegment(_ segment: TranscriptSegmentRecord) async throws {}
    func getTranscript(meetingId: String) async throws -> [TranscriptSegmentRecord] { [] }
    func getSegment(id: String) async throws -> TranscriptSegmentRecord? {
        segments[id]
    }
    func search(query: String) async throws -> [MeetingRecord] { [] }
    func findOrphaned() async throws -> [MeetingRecord] { [] }
    func getSpeakerLabels(meetingId: String) async throws -> [SpeakerLabelRecord] { [] }
    func upsertSpeakerLabel(_ label: SpeakerLabelRecord) async throws {}
}

final class MockDocumentRepositoryForRAG: DocumentRepositoryProtocol, @unchecked Sendable {
    var chunks: [String: DocumentChunkRecord] = [:]

    func getChunk(id: String) async throws -> DocumentChunkRecord? {
        chunks[id]
    }
}
