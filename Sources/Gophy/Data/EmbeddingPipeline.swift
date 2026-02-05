import Foundation

public protocol EmbeddingProviding: Sendable {
    func embed(text: String) async throws -> [Float]
    func embedBatch(texts: [String]) async throws -> [[Float]]
}

extension EmbeddingEngine: EmbeddingProviding {}

public final class EmbeddingPipeline: Sendable {
    private let embeddingEngine: any EmbeddingProviding
    private let vectorSearchService: VectorSearchService
    private let meetingRepository: MeetingRepository
    private let documentRepository: DocumentRepository
    private let batchSize: Int

    public init(
        embeddingEngine: any EmbeddingProviding,
        vectorSearchService: VectorSearchService,
        meetingRepository: MeetingRepository,
        documentRepository: DocumentRepository,
        batchSize: Int = 32
    ) {
        self.embeddingEngine = embeddingEngine
        self.vectorSearchService = vectorSearchService
        self.meetingRepository = meetingRepository
        self.documentRepository = documentRepository
        self.batchSize = batchSize
    }

    public func indexTranscriptSegment(segment: TranscriptSegmentRecord) async throws {
        try await vectorSearchService.delete(id: segment.id)

        let embedding = try await embeddingEngine.embed(text: segment.text)
        try await vectorSearchService.insert(id: segment.id, embedding: embedding)
    }

    public func indexDocumentChunk(chunk: DocumentChunkRecord) async throws {
        try await vectorSearchService.delete(id: chunk.id)

        let embedding = try await embeddingEngine.embed(text: chunk.content)
        try await vectorSearchService.insert(id: chunk.id, embedding: embedding)
    }

    public func indexMeeting(meetingId: String) async throws {
        let segments = try await meetingRepository.getTranscript(meetingId: meetingId)

        guard !segments.isEmpty else {
            return
        }

        try await indexSegmentsBatch(segments)
    }

    public func indexDocument(documentId: String) async throws {
        let chunks = try await documentRepository.getChunks(documentId: documentId)

        guard !chunks.isEmpty else {
            return
        }

        try await indexChunksBatch(chunks)
    }

    private func indexSegmentsBatch(_ segments: [TranscriptSegmentRecord]) async throws {
        let batches = segments.chunked(into: batchSize)

        for batch in batches {
            for segment in batch {
                try await vectorSearchService.delete(id: segment.id)
            }

            let texts = batch.map { $0.text }
            let embeddings = try await embeddingEngine.embedBatch(texts: texts)

            for (index, segment) in batch.enumerated() {
                try await vectorSearchService.insert(id: segment.id, embedding: embeddings[index])
            }
        }
    }

    private func indexChunksBatch(_ chunks: [DocumentChunkRecord]) async throws {
        let batches = chunks.chunked(into: batchSize)

        for batch in batches {
            for chunk in batch {
                try await vectorSearchService.delete(id: chunk.id)
            }

            let texts = batch.map { $0.content }
            let embeddings = try await embeddingEngine.embedBatch(texts: texts)

            for (index, chunk) in batch.enumerated() {
                try await vectorSearchService.insert(id: chunk.id, embedding: embeddings[index])
            }
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
