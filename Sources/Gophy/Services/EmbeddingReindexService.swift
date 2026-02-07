import Foundation

public protocol DocumentRepositoryForReindex: Sendable {
    func listAll() async throws -> [DocumentRecord]
    func getChunks(documentId: String) async throws -> [DocumentChunkRecord]
}

extension DocumentRepository: DocumentRepositoryForReindex {}

public protocol VectorSearchForReindex: Sendable {
    func count() async throws -> Int
}

extension VectorSearchService: VectorSearchForReindex {}

public final class EmbeddingReindexService: Sendable {
    private let embeddingPipeline: any EmbeddingPipelineProtocol
    private let meetingRepository: any MeetingRepositoryProtocol
    private let documentRepository: any DocumentRepositoryForReindex
    private let vectorSearchService: any VectorSearchForReindex
    private let batchSize: Int

    public init(
        embeddingPipeline: any EmbeddingPipelineProtocol,
        meetingRepository: any MeetingRepositoryProtocol,
        documentRepository: any DocumentRepositoryForReindex,
        vectorSearchService: any VectorSearchForReindex,
        batchSize: Int = 32
    ) {
        self.embeddingPipeline = embeddingPipeline
        self.meetingRepository = meetingRepository
        self.documentRepository = documentRepository
        self.vectorSearchService = vectorSearchService
        self.batchSize = batchSize
    }

    public func needsReindex() async -> Bool {
        let currentVersion = UserDefaults.standard.string(forKey: "embeddingModelVersion")
        if currentVersion == "multilingual-e5-small" {
            return false
        }

        do {
            let embeddingCount = try await vectorSearchService.count()
            if embeddingCount == 0 {
                let allMeetings = try await meetingRepository.listAll(limit: nil, offset: 0)
                for meeting in allMeetings {
                    let segments = try await meetingRepository.getTranscript(meetingId: meeting.id)
                    if !segments.isEmpty {
                        return true
                    }
                }

                let allDocuments = try await documentRepository.listAll()
                for document in allDocuments {
                    let chunks = try await documentRepository.getChunks(documentId: document.id)
                    if !chunks.isEmpty {
                        return true
                    }
                }
            }
        } catch {
            return true
        }

        return currentVersion != "multilingual-e5-small"
    }

    public func reindexAll(progress: @escaping @Sendable (Int, Int) -> Void) async throws {
        let allMeetings = try await meetingRepository.listAll(limit: nil, offset: 0)
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
        guard total > 0 else {
            UserDefaults.standard.set("multilingual-e5-small", forKey: "embeddingModelVersion")
            return
        }

        var processed = 0

        let segmentBatches = allSegments.chunked(into: batchSize)
        for batch in segmentBatches {
            for segment in batch {
                try await embeddingPipeline.indexTranscriptSegment(segment: segment)
                processed += 1
                progress(processed, total)
            }
        }

        let chunkBatches = allChunks.chunked(into: batchSize)
        for batch in chunkBatches {
            for chunk in batch {
                try await embeddingPipeline.indexDocumentChunk(chunk: chunk)
                processed += 1
                progress(processed, total)
            }
        }

        UserDefaults.standard.set("multilingual-e5-small", forKey: "embeddingModelVersion")
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
