import Foundation

// MARK: - Protocols for Dependencies

public protocol TextGenerationForSuggestion: Sendable {
    var isLoaded: Bool { get }
    func load() async throws
    func unload()
    func generate(prompt: String, systemPrompt: String, maxTokens: Int) -> AsyncStream<String>
}

extension TextGenerationEngine: TextGenerationForSuggestion {}

public protocol VectorSearchForSuggestion: Sendable {
    func search(query: [Float], limit: Int) async throws -> [VectorSearchResult]
    func insert(id: String, embedding: [Float]) async throws
    func delete(id: String) async throws
    func count() async throws -> Int
}

extension VectorSearchService: VectorSearchForSuggestion {}

public protocol ChatMessageRepoForSuggestion: Sendable {
    func create(_ message: ChatMessageRecord) async throws
    func listForMeeting(meetingId: String) async throws -> [ChatMessageRecord]
    func delete(id: String) async throws
}

public protocol DocumentRepositoryForSuggestion: Sendable {
    func get(id: String) async throws -> DocumentRecord?
    func getChunk(id: String) async throws -> DocumentChunkRecord?
    func getChunks(documentId: String) async throws -> [DocumentChunkRecord]
}

extension DocumentRepository: DocumentRepositoryForSuggestion {}

// MARK: - SuggestionEngine

public actor SuggestionEngine {
    private let textGenerationEngine: any TextGenerationForSuggestion
    private let vectorSearchService: any VectorSearchForSuggestion
    private let embeddingEngine: any EmbeddingProviding
    private let meetingRepository: any MeetingRepositoryProtocol
    private let documentRepository: any DocumentRepositoryForSuggestion
    private let chatMessageRepository: any ChatMessageRepoForSuggestion
    private let autoTriggerInterval: TimeInterval

    private let systemPrompt = """
        You are an AI meeting assistant. Given the current conversation and relevant context \
        from past meetings and documents, provide a concise, actionable suggestion. \
        Keep your response brief and focused on the most important point.
        """

    public init(
        textGenerationEngine: any TextGenerationForSuggestion,
        vectorSearchService: any VectorSearchForSuggestion,
        embeddingEngine: any EmbeddingProviding,
        meetingRepository: any MeetingRepositoryProtocol,
        documentRepository: any DocumentRepositoryForSuggestion,
        chatMessageRepository: any ChatMessageRepoForSuggestion,
        autoTriggerInterval: TimeInterval = 30.0
    ) {
        self.textGenerationEngine = textGenerationEngine
        self.vectorSearchService = vectorSearchService
        self.embeddingEngine = embeddingEngine
        self.meetingRepository = meetingRepository
        self.documentRepository = documentRepository
        self.chatMessageRepository = chatMessageRepository
        self.autoTriggerInterval = autoTriggerInterval
    }

    /// Generate a suggestion manually on demand
    /// - Parameter meetingId: The meeting to generate a suggestion for
    /// - Returns: The complete generated suggestion text
    public func generateSuggestion(meetingId: String) async throws -> String {
        var fullSuggestion = ""

        for await token in generateSuggestionStream(meetingId: meetingId) {
            fullSuggestion += token
        }

        return fullSuggestion
    }

    /// Start automatic suggestions triggered every N seconds of transcript
    /// - Parameters:
    ///   - meetingId: The meeting to generate suggestions for
    ///   - transcriptStream: Stream of incoming transcript segments
    /// - Returns: AsyncStream of complete suggestions (not tokens)
    public nonisolated func startAutoSuggestions(
        meetingId: String,
        transcriptStream: AsyncStream<TranscriptSegment>
    ) -> AsyncStream<String> {
        AsyncStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }

            Task {
                var accumulatedDuration: TimeInterval = 0.0

                for await segment in transcriptStream {
                    let segmentDuration = segment.endTime - segment.startTime
                    accumulatedDuration += segmentDuration

                    if accumulatedDuration >= self.autoTriggerInterval {
                        do {
                            let suggestion = try await self.generateSuggestion(meetingId: meetingId)
                            continuation.yield(suggestion)
                            accumulatedDuration = 0.0
                        } catch {
                            print("Error auto-generating suggestion: \(error)")
                            accumulatedDuration = 0.0
                        }
                    }
                }

                continuation.finish()
            }
        }
    }

    /// Generate a suggestion with streaming tokens
    /// - Parameter meetingId: The meeting to generate a suggestion for
    /// - Returns: AsyncStream of generated tokens
    /// - Throws: Errors are not thrown directly; they terminate the stream
    public nonisolated func generateSuggestionStream(meetingId: String) -> AsyncStream<String> {
        AsyncStream { [weak self] continuation in
            guard let self = self else {
                continuation.finish()
                return
            }

            Task {
                do {
                    // Get last 60 seconds of transcript
                    let transcript = try await self.getRecentTranscript(meetingId: meetingId, lastSeconds: 60.0)

                    // Get RAG context
                    let ragContext = try await self.getRAGContext(for: transcript)

                    // Build prompt
                    let prompt = await self.buildPrompt(transcript: transcript, ragContext: ragContext)

                    // Generate suggestion
                    var fullSuggestion = ""
                    let stream = self.textGenerationEngine.generate(
                        prompt: prompt,
                        systemPrompt: self.systemPrompt,
                        maxTokens: 150
                    )

                    for await token in stream {
                        fullSuggestion += token
                        continuation.yield(token)
                    }

                    // Store suggestion as chat message
                    do {
                        try await self.storeSuggestion(fullSuggestion, meetingId: meetingId)
                    } catch {
                        // Log storage error but don't fail the entire suggestion
                        print("Error storing suggestion: \(error)")
                    }

                    continuation.finish()
                } catch {
                    print("Error generating suggestion: \(error)")
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Private Methods

    private func getRecentTranscript(meetingId: String, lastSeconds: TimeInterval) async throws -> [TranscriptSegmentRecord] {
        let allSegments = try await meetingRepository.getTranscript(meetingId: meetingId)

        guard !allSegments.isEmpty else {
            return []
        }

        // Get segments from the last N seconds
        let latestTime = allSegments.map { $0.endTime }.max() ?? 0
        let cutoffTime = latestTime - lastSeconds

        return allSegments.filter { $0.endTime >= cutoffTime }
    }

    private enum RAGContextItem {
        case transcriptSegment(TranscriptSegmentRecord)
        case documentChunk(DocumentChunkRecord)
    }

    private func getRAGContext(for transcript: [TranscriptSegmentRecord]) async throws -> [RAGContextItem] {
        guard !transcript.isEmpty else {
            return []
        }

        // Combine transcript text for embedding
        let combinedText = transcript.map { $0.text }.joined(separator: " ")

        // Embed query
        let queryEmbedding = try await embeddingEngine.embed(text: combinedText)

        // Search for similar segments and chunks
        let searchResults = try await vectorSearchService.search(query: queryEmbedding, limit: 5)

        // Fetch full segments or chunks
        var contextItems: [RAGContextItem] = []
        for result in searchResults {
            // Try as transcript segment first
            if let segment = try await meetingRepository.getSegment(id: result.id) {
                contextItems.append(.transcriptSegment(segment))
            } else if let chunk = try await documentRepository.getChunk(id: result.id) {
                // Try as document chunk
                contextItems.append(.documentChunk(chunk))
            }
        }

        return contextItems
    }

    private func buildPrompt(transcript: [TranscriptSegmentRecord], ragContext: [RAGContextItem]) -> String {
        var prompt = "Current conversation:\n"

        for segment in transcript {
            prompt += "[\(segment.speaker)] \(segment.text)\n"
        }

        if !ragContext.isEmpty {
            prompt += "\nRelevant context:\n"
            for item in ragContext {
                switch item {
                case .transcriptSegment(let segment):
                    prompt += "[Past conversation - \(segment.speaker)] \(segment.text)\n"
                case .documentChunk(let chunk):
                    prompt += "[Document - page \(chunk.pageNumber)] \(chunk.content)\n"
                }
            }
        }

        prompt += "\nSuggestion:"

        return prompt
    }

    private func storeSuggestion(_ suggestion: String, meetingId: String) async throws {
        let message = ChatMessageRecord(
            id: UUID().uuidString,
            role: "assistant",
            content: suggestion,
            meetingId: meetingId,
            createdAt: Date()
        )

        try await chatMessageRepository.create(message)
    }
}
