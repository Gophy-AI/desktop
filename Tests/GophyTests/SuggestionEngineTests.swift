import XCTest
@testable import Gophy

final class SuggestionEngineTests: XCTestCase {
    private var engine: SuggestionEngine!
    private var mockTextGen: MockTextGenerationForSuggestion!
    private var mockVectorSearch: MockVectorSearchForSuggestion!
    private var mockEmbedding: MockEmbeddingForSuggestion!
    private var mockMeetingRepo: MockMeetingRepoForSuggestion!
    private var mockDocumentRepo: MockDocumentRepoForSuggestion!
    private var mockChatRepo: MockChatMessageRepoForSuggestion!

    override func setUp() async throws {
        try await super.setUp()

        mockTextGen = MockTextGenerationForSuggestion()
        mockVectorSearch = MockVectorSearchForSuggestion()
        mockEmbedding = MockEmbeddingForSuggestion()
        mockMeetingRepo = MockMeetingRepoForSuggestion()
        mockDocumentRepo = MockDocumentRepoForSuggestion()
        mockChatRepo = MockChatMessageRepoForSuggestion()

        engine = SuggestionEngine(
            textGenerationEngine: mockTextGen,
            vectorSearchService: mockVectorSearch,
            embeddingEngine: mockEmbedding,
            meetingRepository: mockMeetingRepo,
            documentRepository: mockDocumentRepo,
            chatMessageRepository: mockChatRepo,
            autoTriggerInterval: 30.0
        )
    }

    func testSuggestionGeneratedFromTranscriptAndRAGContext() async throws {
        // Set up transcript
        let transcriptSegments = [
            TranscriptSegmentRecord(
                id: "seg1",
                meetingId: "meeting1",
                text: "We should discuss the quarterly results",
                speaker: "You",
                startTime: 0.0,
                endTime: 5.0,
                createdAt: Date()
            )
        ]
        await mockMeetingRepo.setTranscript(for: "meeting1", segments: transcriptSegments)

        // Set up RAG results
        await mockEmbedding.setEmbedding(Array(repeating: 0.1, count: 768))
        await mockVectorSearch.setResults([
            VectorSearchResult(id: "seg2", distance: 0.5),
            VectorSearchResult(id: "seg3", distance: 0.6)
        ])
        await mockMeetingRepo.setSegment(
            "seg2",
            TranscriptSegmentRecord(
                id: "seg2",
                meetingId: "meeting0",
                text: "Last quarter we achieved 20% growth",
                speaker: "Others",
                startTime: 0.0,
                endTime: 5.0,
                createdAt: Date()
            )
        )
        await mockMeetingRepo.setSegment(
            "seg3",
            TranscriptSegmentRecord(
                id: "seg3",
                meetingId: "meeting0",
                text: "Focus on customer retention metrics",
                speaker: "You",
                startTime: 10.0,
                endTime: 15.0,
                createdAt: Date()
            )
        )

        // Set up text generation
        await mockTextGen.setTokens(["Based", " on", " past", " results", ",", " focus", " on", " growth", " metrics"])

        let suggestion = try await engine.generateSuggestion(meetingId: "meeting1")

        XCTAssertEqual(suggestion, "Based on past results, focus on growth metrics")
        let savedMessages = await mockChatRepo.savedMessages
        XCTAssertEqual(savedMessages.count, 1)
        let savedMessage = savedMessages.first!
        XCTAssertEqual(savedMessage.role, "assistant")
        XCTAssertEqual(savedMessage.content, "Based on past results, focus on growth metrics")
        XCTAssertEqual(savedMessage.meetingId, "meeting1")
    }

    func testManualTriggerOnDemand() async throws {
        await mockMeetingRepo.setTranscript(for: "meeting1", segments: [])
        await mockEmbedding.setEmbedding(Array(repeating: 0.1, count: 768))
        await mockVectorSearch.setResults([])
        await mockTextGen.setTokens(["Manual", " suggestion"])

        let suggestion = try await engine.generateSuggestion(meetingId: "meeting1")

        XCTAssertEqual(suggestion, "Manual suggestion")
    }

    func testSuggestionsStoredAsChatMessages() async throws {
        await mockMeetingRepo.setTranscript(for: "meeting1", segments: [
            TranscriptSegmentRecord(
                id: "seg1",
                meetingId: "meeting1",
                text: "Test transcript",
                speaker: "You",
                startTime: 0.0,
                endTime: 1.0,
                createdAt: Date()
            )
        ])
        await mockEmbedding.setEmbedding(Array(repeating: 0.1, count: 768))
        await mockVectorSearch.setResults([])
        await mockTextGen.setTokens(["Stored", " message"])

        _ = try await engine.generateSuggestion(meetingId: "meeting1")

        let savedMessages = await mockChatRepo.savedMessages
        XCTAssertEqual(savedMessages.count, 1)
        XCTAssertEqual(savedMessages.first?.role, "assistant")
        XCTAssertEqual(savedMessages.first?.content, "Stored message")
    }

    func testAutomaticTriggerEvery30SecondsOfTranscript() async throws {
        // Set up test data
        await mockMeetingRepo.setTranscript(for: "meeting1", segments: [])
        await mockEmbedding.setEmbedding(Array(repeating: 0.1, count: 768))
        await mockVectorSearch.setResults([])
        await mockTextGen.setTokens(["Auto", " suggestion"])

        // Create transcript stream with segments totaling 30+ seconds
        let (stream, continuation) = AsyncStream.makeStream(of: TranscriptSegment.self)

        let expectation = expectation(description: "Auto-trigger fires after 30 seconds")
        let localEngine = engine!

        Task { @Sendable in
            var suggestionCount = 0
            for await _ in localEngine.startAutoSuggestions(meetingId: "meeting1", transcriptStream: stream) {
                suggestionCount += 1
                if suggestionCount == 1 {
                    expectation.fulfill()
                }
            }
        }

        // Yield segments totaling 35 seconds (should trigger once)
        continuation.yield(TranscriptSegment(text: "First", startTime: 0, endTime: 15, speaker: "You"))
        try await Task.sleep(nanoseconds: 50_000_000)
        continuation.yield(TranscriptSegment(text: "Second", startTime: 15, endTime: 35, speaker: "You"))
        try await Task.sleep(nanoseconds: 50_000_000)
        continuation.finish()

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testStreamingSuggestionYieldsTokens() async throws {
        await mockMeetingRepo.setTranscript(for: "meeting1", segments: [
            TranscriptSegmentRecord(
                id: "seg1",
                meetingId: "meeting1",
                text: "Test",
                speaker: "You",
                startTime: 0.0,
                endTime: 1.0,
                createdAt: Date()
            )
        ])
        await mockEmbedding.setEmbedding(Array(repeating: 0.1, count: 768))
        await mockVectorSearch.setResults([])
        await mockTextGen.setTokens(["Token", " 1", " Token", " 2"])

        var tokens: [String] = []
        for await token in engine.generateSuggestionStream(meetingId: "meeting1") {
            tokens.append(token)
        }

        XCTAssertEqual(tokens, ["Token", " 1", " Token", " 2"])
    }

    func testRAGContextIncludesDocumentChunks() async throws {
        // Set up transcript
        await mockMeetingRepo.setTranscript(for: "meeting1", segments: [
            TranscriptSegmentRecord(
                id: "seg1",
                meetingId: "meeting1",
                text: "Discuss the product roadmap",
                speaker: "You",
                startTime: 0.0,
                endTime: 5.0,
                createdAt: Date()
            )
        ])

        // Set up RAG results: one segment, one document chunk
        await mockEmbedding.setEmbedding(Array(repeating: 0.1, count: 768))
        await mockVectorSearch.setResults([
            VectorSearchResult(id: "seg2", distance: 0.5),
            VectorSearchResult(id: "chunk1", distance: 0.6)
        ])
        await mockMeetingRepo.setSegment(
            "seg2",
            TranscriptSegmentRecord(
                id: "seg2",
                meetingId: "meeting0",
                text: "Previous roadmap discussion",
                speaker: "Others",
                startTime: 0.0,
                endTime: 5.0,
                createdAt: Date()
            )
        )
        await mockDocumentRepo.setChunk(
            "chunk1",
            DocumentChunkRecord(
                id: "chunk1",
                documentId: "doc1",
                content: "Q3 product features include AI integration",
                chunkIndex: 0,
                pageNumber: 1,
                createdAt: Date()
            )
        )

        await mockTextGen.setTokens(["Combined", " context"])

        let suggestion = try await engine.generateSuggestion(meetingId: "meeting1")

        XCTAssertEqual(suggestion, "Combined context")
    }
}

// MARK: - Mock Text Generation Engine

actor MockTextGenerationForSuggestion: TextGenerationForSuggestion {
    nonisolated var isLoaded: Bool { true }
    private var tokensToGenerate: [String] = []

    func load() async throws {
        // No-op
    }

    nonisolated func unload() {
        // No-op
    }

    nonisolated func generate(prompt: String, systemPrompt: String, maxTokens: Int) -> AsyncStream<String> {
        let capturedSelf = self
        return AsyncStream { continuation in
            Task { @Sendable in
                let tokens = await capturedSelf.getTokens()
                for token in tokens {
                    continuation.yield(token)
                }
                continuation.finish()
            }
        }
    }

    func setTokens(_ tokens: [String]) {
        tokensToGenerate = tokens
    }

    private func getTokens() -> [String] {
        tokensToGenerate
    }
}

// MARK: - Mock Vector Search

actor MockVectorSearchForSuggestion: VectorSearchForSuggestion {
    private var resultsToReturn: [VectorSearchResult] = []

    func search(query: [Float], limit: Int) async throws -> [VectorSearchResult] {
        resultsToReturn
    }

    func insert(id: String, embedding: [Float]) async throws {
        // No-op
    }

    func delete(id: String) async throws {
        // No-op
    }

    func count() async throws -> Int {
        0
    }

    func setResults(_ results: [VectorSearchResult]) {
        resultsToReturn = results
    }
}

// MARK: - Mock Embedding Engine

actor MockEmbeddingForSuggestion: EmbeddingProviding {
    private var embeddingToReturn: [Float] = []

    func embed(text: String, mode: EmbeddingMode = .passage) async throws -> [Float] {
        embeddingToReturn
    }

    func embedBatch(texts: [String], mode: EmbeddingMode = .passage) async throws -> [[Float]] {
        texts.map { _ in embeddingToReturn }
    }

    func setEmbedding(_ embedding: [Float]) {
        embeddingToReturn = embedding
    }
}

// MARK: - Mock Meeting Repository

actor MockMeetingRepoForSuggestion: MeetingRepositoryProtocol {
    private var transcripts: [String: [TranscriptSegmentRecord]] = [:]
    private var segmentsById: [String: TranscriptSegmentRecord] = [:]

    func getTranscript(meetingId: String) async throws -> [TranscriptSegmentRecord] {
        transcripts[meetingId] ?? []
    }

    func getSegment(id: String) async throws -> TranscriptSegmentRecord? {
        segmentsById[id]
    }

    func create(_ meeting: MeetingRecord) async throws {
        // No-op
    }

    func update(_ meeting: MeetingRecord) async throws {
        // No-op
    }

    func get(id: String) async throws -> MeetingRecord? {
        nil
    }

    func listAll(limit: Int?, offset: Int) async throws -> [MeetingRecord] {
        []
    }

    func delete(id: String) async throws {
        // No-op
    }

    func addTranscriptSegment(_ segment: TranscriptSegmentRecord) async throws {
        // No-op
    }

    func search(query: String) async throws -> [MeetingRecord] {
        []
    }

    func findOrphaned() async throws -> [MeetingRecord] {
        []
    }

    func getSpeakerLabels(meetingId: String) async throws -> [SpeakerLabelRecord] {
        []
    }

    func upsertSpeakerLabel(_ label: SpeakerLabelRecord) async throws {
        // No-op
    }

    func setTranscript(for meetingId: String, segments: [TranscriptSegmentRecord]) {
        transcripts[meetingId] = segments
    }

    func setSegment(_ id: String, _ segment: TranscriptSegmentRecord) {
        segmentsById[id] = segment
    }
}

// MARK: - Mock Document Repository

actor MockDocumentRepoForSuggestion: DocumentRepositoryForSuggestion {
    private var chunksById: [String: DocumentChunkRecord] = [:]

    func get(id: String) async throws -> DocumentRecord? {
        nil
    }

    func getChunk(id: String) async throws -> DocumentChunkRecord? {
        chunksById[id]
    }

    func getChunks(documentId: String) async throws -> [DocumentChunkRecord] {
        []
    }

    func setChunk(_ id: String, _ chunk: DocumentChunkRecord) {
        chunksById[id] = chunk
    }
}

// MARK: - Mock Chat Message Repository

actor MockChatMessageRepoForSuggestion: ChatMessageRepoForSuggestion {
    private(set) var savedMessages: [ChatMessageRecord] = []

    func create(_ message: ChatMessageRecord) async throws {
        savedMessages.append(message)
    }

    func listForMeeting(meetingId: String) async throws -> [ChatMessageRecord] {
        savedMessages.filter { $0.meetingId == meetingId }
    }

    func delete(id: String) async throws {
        // No-op
    }
}
