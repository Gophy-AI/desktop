import Foundation

public protocol TextGenerationProviding: Sendable {
    func generate(prompt: String, systemPrompt: String, maxTokens: Int) -> AsyncStream<String>
}

public protocol VectorSearching: Sendable {
    func search(query: [Float], limit: Int) async throws -> [VectorSearchResult]
}

public protocol DocumentRepositoryProtocol: Sendable {
    func getChunk(id: String) async throws -> DocumentChunkRecord?
}

extension TextGenerationEngine: TextGenerationProviding {}
extension VectorSearchService: VectorSearching {}
extension DocumentRepository: DocumentRepositoryProtocol {}

/// Adapter that wraps TextGenerationProviding as a TextGenerationProvider for RAG
private final class TextGenProvidingAdapter: TextGenerationProvider, @unchecked Sendable {
    private let engine: any TextGenerationProviding

    init(engine: any TextGenerationProviding) {
        self.engine = engine
    }

    func generate(prompt: String, systemPrompt: String, maxTokens: Int, temperature: Double) -> AsyncThrowingStream<String, Error> {
        let stream = engine.generate(prompt: prompt, systemPrompt: systemPrompt, maxTokens: maxTokens)
        return AsyncThrowingStream { continuation in
            Task {
                for await token in stream {
                    continuation.yield(token)
                }
                continuation.finish()
            }
        }
    }
}

public final class RAGPipeline: Sendable {
    private let embeddingEngine: any EmbeddingProviding
    private let vectorSearchService: any VectorSearching
    private let textGenProvider: any TextGenerationProvider
    private let meetingRepository: any MeetingRepositoryProtocol
    private let documentRepository: any DocumentRepositoryProtocol
    private let topK: Int

    /// Initialize with a TextGenerationProvider directly
    public init(
        embeddingEngine: any EmbeddingProviding,
        vectorSearchService: any VectorSearching,
        textGenProvider: any TextGenerationProvider,
        meetingRepository: any MeetingRepositoryProtocol,
        documentRepository: any DocumentRepositoryProtocol,
        topK: Int = 10
    ) {
        self.embeddingEngine = embeddingEngine
        self.vectorSearchService = vectorSearchService
        self.textGenProvider = textGenProvider
        self.meetingRepository = meetingRepository
        self.documentRepository = documentRepository
        self.topK = topK
    }

    /// Initialize with the legacy TextGenerationProviding protocol (backwards compatible)
    public init(
        embeddingEngine: any EmbeddingProviding,
        vectorSearchService: any VectorSearching,
        textGenerationEngine: any TextGenerationProviding,
        meetingRepository: any MeetingRepositoryProtocol,
        documentRepository: any DocumentRepositoryProtocol,
        topK: Int = 10
    ) {
        self.embeddingEngine = embeddingEngine
        self.vectorSearchService = vectorSearchService
        self.textGenProvider = TextGenProvidingAdapter(engine: textGenerationEngine)
        self.meetingRepository = meetingRepository
        self.documentRepository = documentRepository
        self.topK = topK
    }

    public func query(question: String, scope: RAGScope) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                do {
                    let embedding = try await embeddingEngine.embed(text: question, mode: .query)

                    let searchResults = try await vectorSearchService.search(query: embedding, limit: topK)

                    let filteredResults = try await filterResults(searchResults, scope: scope)

                    let contextChunks = try await fetchChunks(for: filteredResults)

                    let context = contextChunks.joined(separator: "\n\n")

                    let systemPrompt = """
                        Answer the question based on the provided context. If the context does not contain sufficient information to answer the question, say so clearly.

                        Context:
                        \(context)
                        """

                    let prompt = "Question: \(question)"

                    let responseStream = textGenProvider.generate(
                        prompt: prompt,
                        systemPrompt: systemPrompt,
                        maxTokens: 512,
                        temperature: 0.7
                    )

                    for try await token in responseStream {
                        continuation.yield(token)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
        }
    }

    private func filterResults(_ results: [VectorSearchResult], scope: RAGScope) async throws -> [VectorSearchResult] {
        switch scope {
        case .all:
            return results

        case .meetings:
            var filtered: [VectorSearchResult] = []
            for result in results {
                if (try? await meetingRepository.getSegment(id: result.id)) != nil {
                    filtered.append(result)
                }
            }
            return filtered

        case .documents:
            var filtered: [VectorSearchResult] = []
            for result in results {
                if (try? await documentRepository.getChunk(id: result.id)) != nil {
                    filtered.append(result)
                }
            }
            return filtered

        case .meeting(let meetingId):
            var filtered: [VectorSearchResult] = []
            for result in results {
                if let segment = try? await meetingRepository.getSegment(id: result.id),
                   segment.meetingId == meetingId {
                    filtered.append(result)
                }
            }
            return filtered
        }
    }

    private func fetchChunks(for results: [VectorSearchResult]) async throws -> [String] {
        var chunks: [String] = []

        for result in results {
            if let segment = try? await meetingRepository.getSegment(id: result.id) {
                chunks.append(segment.text)
            } else if let chunk = try? await documentRepository.getChunk(id: result.id) {
                chunks.append(chunk.content)
            }
        }

        return chunks
    }
}
