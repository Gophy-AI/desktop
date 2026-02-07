import Testing
import Foundation
import MLXLMCommon
@testable import Gophy

// MARK: - Mock Protocols for Built-in Tools

private actor MockDocumentRepoForTools: DocumentRepositoryForTools {
    var createdDocuments: [DocumentRecord] = []
    var createdChunks: [DocumentChunkRecord] = []
    var deletedDocumentIds: [String] = []

    func createDocument(_ document: DocumentRecord) async throws {
        createdDocuments.append(document)
    }

    func addChunk(_ chunk: DocumentChunkRecord) async throws {
        createdChunks.append(chunk)
    }

    func deleteDocument(id: String) async throws {
        deletedDocumentIds.append(id)
    }
}

private actor MockEmbeddingPipelineForBuiltIn: EmbeddingPipelineProtocol {
    var indexedChunks: [DocumentChunkRecord] = []

    func indexMeeting(meetingId: String) async throws {}
    func indexDocument(documentId: String) async throws {}
    func indexTranscriptSegment(segment: TranscriptSegmentRecord) async throws {}

    func indexDocumentChunk(chunk: DocumentChunkRecord) async throws {
        indexedChunks.append(chunk)
    }
}

private actor MockChatMessageRepoForBuiltIn: ChatMessageRepoForSuggestion {
    var createdMessages: [ChatMessageRecord] = []
    var deletedMessageIds: [String] = []

    func create(_ message: ChatMessageRecord) async throws {
        createdMessages.append(message)
    }

    func listForMeeting(meetingId: String) async throws -> [ChatMessageRecord] {
        createdMessages.filter { $0.meetingId == meetingId }
    }

    func delete(id: String) async throws {
        deletedMessageIds.append(id)
    }
}

private actor MockEmbeddingProviderForTools: EmbeddingProviding {
    var embedResult: [Float] = Array(repeating: 0.1, count: 384)

    func embed(text: String, mode: EmbeddingMode) async throws -> [Float] {
        embedResult
    }

    func embedBatch(texts: [String], mode: EmbeddingMode) async throws -> [[Float]] {
        texts.map { _ in embedResult }
    }
}

private actor MockVectorSearchForTools: VectorSearching {
    var searchResults: [VectorSearchResult] = []

    func search(query: [Float], limit: Int) async throws -> [VectorSearchResult] {
        Array(searchResults.prefix(limit))
    }

    func setResults(_ results: [VectorSearchResult]) {
        searchResults = results
    }
}

private actor MockMeetingRepoForBuiltIn: MeetingRepositoryProtocol {
    var transcripts: [String: [TranscriptSegmentRecord]] = [:]

    func create(_ meeting: MeetingRecord) async throws {}
    func update(_ meeting: MeetingRecord) async throws {}
    func get(id: String) async throws -> MeetingRecord? { nil }
    func listAll(limit: Int?, offset: Int) async throws -> [MeetingRecord] { [] }
    func delete(id: String) async throws {}
    func addTranscriptSegment(_ segment: TranscriptSegmentRecord) async throws {}
    func search(query: String) async throws -> [MeetingRecord] { [] }
    func findOrphaned() async throws -> [MeetingRecord] { [] }
    func getSpeakerLabels(meetingId: String) async throws -> [SpeakerLabelRecord] { [] }
    func upsertSpeakerLabel(_ label: SpeakerLabelRecord) async throws {}

    func getTranscript(meetingId: String) async throws -> [TranscriptSegmentRecord] {
        transcripts[meetingId] ?? []
    }

    func getSegment(id: String) async throws -> TranscriptSegmentRecord? {
        for segments in transcripts.values {
            if let segment = segments.first(where: { $0.id == id }) {
                return segment
            }
        }
        return nil
    }

    func setTranscript(meetingId: String, segments: [TranscriptSegmentRecord]) {
        transcripts[meetingId] = segments
    }
}

private actor MockDocumentRepoForSearch: DocumentRepositoryProtocol {
    var chunks: [String: DocumentChunkRecord] = [:]

    func getChunk(id: String) async throws -> DocumentChunkRecord? {
        chunks[id]
    }

    func setChunk(_ chunk: DocumentChunkRecord) {
        chunks[chunk.id] = chunk
    }
}

private final class MockTextGenerationForTools: TextGenerationProviding, @unchecked Sendable {
    var generateResult: String = "Generated summary text"

    func generate(prompt: String, systemPrompt: String, maxTokens: Int) -> AsyncStream<String> {
        let result = generateResult
        return AsyncStream { continuation in
            continuation.yield(result)
            continuation.finish()
        }
    }
}

// MARK: - RememberTool Tests

@Suite("BuiltInTools - remember")
struct RememberToolTests {

    @Test("handler creates DocumentRecord with name 'Memory: <label>'")
    func rememberCreatesDocument() async throws {
        let docRepo = MockDocumentRepoForTools()
        let embeddingPipeline = MockEmbeddingPipelineForBuiltIn()

        let tool = BuiltInTools.remember(
            documentRepository: docRepo,
            embeddingPipeline: embeddingPipeline
        )

        let toolCall = ToolCall(
            function: ToolCall.Function(
                name: "remember",
                arguments: [
                    "content": "Important meeting notes" as any Sendable,
                    "label": "Q4 Review" as any Sendable,
                ]
            )
        )

        _ = try await toolCall.execute(with: tool)

        let docs = await docRepo.createdDocuments
        #expect(docs.count == 1)
        #expect(docs[0].name == "Memory: Q4 Review")
        #expect(docs[0].type == "memory")
        #expect(docs[0].status == "ready")
    }

    @Test("handler creates DocumentChunkRecord and indexes via EmbeddingPipeline")
    func rememberCreatesChunkAndIndexes() async throws {
        let docRepo = MockDocumentRepoForTools()
        let embeddingPipeline = MockEmbeddingPipelineForBuiltIn()

        let tool = BuiltInTools.remember(
            documentRepository: docRepo,
            embeddingPipeline: embeddingPipeline
        )

        let toolCall = ToolCall(
            function: ToolCall.Function(
                name: "remember",
                arguments: [
                    "content": "Remember this fact" as any Sendable,
                    "label": "Fact" as any Sendable,
                ]
            )
        )

        _ = try await toolCall.execute(with: tool)

        let chunks = await docRepo.createdChunks
        #expect(chunks.count == 1)
        #expect(chunks[0].content == "Remember this fact")

        let indexedChunks = await embeddingPipeline.indexedChunks
        #expect(indexedChunks.count == 1)
        #expect(indexedChunks[0].content == "Remember this fact")
    }

    @Test("output contains the created document ID")
    func rememberOutputContainsDocumentId() async throws {
        let docRepo = MockDocumentRepoForTools()
        let embeddingPipeline = MockEmbeddingPipelineForBuiltIn()

        let tool = BuiltInTools.remember(
            documentRepository: docRepo,
            embeddingPipeline: embeddingPipeline
        )

        let toolCall = ToolCall(
            function: ToolCall.Function(
                name: "remember",
                arguments: [
                    "content": "Some content" as any Sendable,
                    "label": "Label" as any Sendable,
                ]
            )
        )

        let output = try await toolCall.execute(with: tool)
        #expect(!output.documentId.isEmpty)
        #expect(output.message.contains("saved"))
    }
}

// MARK: - TakeNoteTool Tests

@Suite("BuiltInTools - takeNote")
struct TakeNoteToolTests {

    @Test("handler creates ChatMessageRecord with role 'note'")
    func takeNoteCreatesMessage() async throws {
        let chatRepo = MockChatMessageRepoForBuiltIn()

        let tool = BuiltInTools.takeNote(chatMessageRepository: chatRepo)

        let toolCall = ToolCall(
            function: ToolCall.Function(
                name: "take_note",
                arguments: [
                    "text": "Follow up with client" as any Sendable
                ]
            )
        )

        _ = try await toolCall.execute(with: tool)

        let messages = await chatRepo.createdMessages
        #expect(messages.count == 1)
        #expect(messages[0].role == "note")
        #expect(messages[0].content == "Follow up with client")
    }

    @Test("handler associates note with meetingId when provided")
    func takeNoteWithMeetingId() async throws {
        let chatRepo = MockChatMessageRepoForBuiltIn()

        let tool = BuiltInTools.takeNote(chatMessageRepository: chatRepo)

        let toolCall = ToolCall(
            function: ToolCall.Function(
                name: "take_note",
                arguments: [
                    "text": "Action item from meeting" as any Sendable,
                    "meetingId": "meeting-123" as any Sendable,
                ]
            )
        )

        _ = try await toolCall.execute(with: tool)

        let messages = await chatRepo.createdMessages
        #expect(messages.count == 1)
        #expect(messages[0].meetingId == "meeting-123")
    }

    @Test("output confirms note was saved")
    func takeNoteOutputConfirms() async throws {
        let chatRepo = MockChatMessageRepoForBuiltIn()

        let tool = BuiltInTools.takeNote(chatMessageRepository: chatRepo)

        let toolCall = ToolCall(
            function: ToolCall.Function(
                name: "take_note",
                arguments: [
                    "text": "Important note" as any Sendable
                ]
            )
        )

        let output = try await toolCall.execute(with: tool)
        #expect(!output.noteId.isEmpty)
        #expect(output.message.contains("saved"))
    }
}

// MARK: - SearchKnowledgeTool Tests

@Suite("BuiltInTools - searchKnowledge")
struct SearchKnowledgeToolTests {

    @Test("handler calls embed then search and returns formatted results")
    func searchReturnsFormattedResults() async throws {
        let embeddingProvider = MockEmbeddingProviderForTools()
        let vectorSearch = MockVectorSearchForTools()
        let docRepo = MockDocumentRepoForSearch()

        let chunk = DocumentChunkRecord(
            id: "chunk-1",
            documentId: "doc-1",
            content: "Relevant knowledge text",
            chunkIndex: 0,
            pageNumber: 1,
            createdAt: Date()
        )
        await docRepo.setChunk(chunk)
        await vectorSearch.setResults([
            VectorSearchResult(id: "chunk-1", distance: 0.1)
        ])

        let meetingRepo = MockMeetingRepoForBuiltIn()

        let tool = BuiltInTools.searchKnowledge(
            embeddingEngine: embeddingProvider,
            vectorSearchService: vectorSearch,
            meetingRepository: meetingRepo,
            documentRepository: docRepo
        )

        let toolCall = ToolCall(
            function: ToolCall.Function(
                name: "search_knowledge",
                arguments: ["query": "knowledge" as any Sendable]
            )
        )

        let output = try await toolCall.execute(with: tool)
        #expect(output.results.count == 1)
        #expect(output.results[0].text == "Relevant knowledge text")
    }

    @Test("empty results return message indicating no results")
    func searchEmptyResults() async throws {
        let embeddingProvider = MockEmbeddingProviderForTools()
        let vectorSearch = MockVectorSearchForTools()
        let docRepo = MockDocumentRepoForSearch()
        let meetingRepo = MockMeetingRepoForBuiltIn()

        let tool = BuiltInTools.searchKnowledge(
            embeddingEngine: embeddingProvider,
            vectorSearchService: vectorSearch,
            meetingRepository: meetingRepo,
            documentRepository: docRepo
        )

        let toolCall = ToolCall(
            function: ToolCall.Function(
                name: "search_knowledge",
                arguments: ["query": "nonexistent" as any Sendable]
            )
        )

        let output = try await toolCall.execute(with: tool)
        #expect(output.results.isEmpty)
    }
}

// MARK: - GenerateSummaryTool Tests

@Suite("BuiltInTools - generateSummary")
struct GenerateSummaryToolTests {

    @Test("handler fetches transcript and generates summary")
    func generateSummaryFetchesAndGenerates() async throws {
        let meetingRepo = MockMeetingRepoForBuiltIn()
        let textGen = MockTextGenerationForTools()

        let segments = [
            TranscriptSegmentRecord(
                id: "seg-1",
                meetingId: "meeting-1",
                text: "Welcome to the meeting",
                speaker: "Host",
                startTime: 0.0,
                endTime: 5.0,
                createdAt: Date()
            ),
            TranscriptSegmentRecord(
                id: "seg-2",
                meetingId: "meeting-1",
                text: "Let's discuss the roadmap",
                speaker: "Host",
                startTime: 5.0,
                endTime: 10.0,
                createdAt: Date()
            ),
        ]
        await meetingRepo.setTranscript(meetingId: "meeting-1", segments: segments)

        let tool = BuiltInTools.generateSummary(
            meetingRepository: meetingRepo,
            textGenerationEngine: textGen
        )

        let toolCall = ToolCall(
            function: ToolCall.Function(
                name: "generate_summary",
                arguments: ["meetingId": "meeting-1" as any Sendable]
            )
        )

        let output = try await toolCall.execute(with: tool)
        #expect(!output.summary.isEmpty)
        #expect(output.summary == "Generated summary text")
    }

    @Test("handler returns descriptive message when transcript is empty")
    func generateSummaryEmptyTranscript() async throws {
        let meetingRepo = MockMeetingRepoForBuiltIn()
        let textGen = MockTextGenerationForTools()

        let tool = BuiltInTools.generateSummary(
            meetingRepository: meetingRepo,
            textGenerationEngine: textGen
        )

        let toolCall = ToolCall(
            function: ToolCall.Function(
                name: "generate_summary",
                arguments: ["meetingId": "empty-meeting" as any Sendable]
            )
        )

        let output = try await toolCall.execute(with: tool)
        #expect(output.summary.contains("No transcript"))
    }
}
