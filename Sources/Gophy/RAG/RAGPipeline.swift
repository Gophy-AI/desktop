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

public final class RAGPipeline: Sendable {
    private let embeddingEngine: any EmbeddingProviding
    private let vectorSearchService: any VectorSearching
    private let textGenerationEngine: any TextGenerationProviding
    private let meetingRepository: any MeetingRepositoryProtocol
    private let documentRepository: any DocumentRepositoryProtocol
    private let topK: Int

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
        self.textGenerationEngine = textGenerationEngine
        self.meetingRepository = meetingRepository
        self.documentRepository = documentRepository
        self.topK = topK
    }

    public func query(question: String, scope: RAGScope) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                do {
                    let embedding = try await embeddingEngine.embed(text: question)

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

                    let responseStream = textGenerationEngine.generate(
                        prompt: prompt,
                        systemPrompt: systemPrompt,
                        maxTokens: 512
                    )

                    for await token in responseStream {
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
