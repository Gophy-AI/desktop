import Foundation
import MLXLMCommon

public enum BuiltInTools {

    // MARK: - remember

    public static func remember(
        documentRepository: any DocumentRepositoryForTools,
        embeddingPipeline: any EmbeddingPipelineProtocol
    ) -> Tool<RememberInput, RememberOutput> {
        Tool<RememberInput, RememberOutput>(
            name: "remember",
            description: "Save information to the knowledge base for later recall.",
            parameters: [
                .required("content", type: .string, description: "The content to remember"),
                .required("label", type: .string, description: "A short label for this memory"),
            ],
            handler: { @Sendable input in
                let documentId = UUID().uuidString
                let chunkId = UUID().uuidString

                let document = DocumentRecord(
                    id: documentId,
                    name: "Memory: \(input.label)",
                    type: "memory",
                    path: "",
                    status: "ready",
                    pageCount: 1,
                    createdAt: Date()
                )
                try await documentRepository.createDocument(document)

                let chunk = DocumentChunkRecord(
                    id: chunkId,
                    documentId: documentId,
                    content: input.content,
                    chunkIndex: 0,
                    pageNumber: 1,
                    createdAt: Date()
                )
                try await documentRepository.addChunk(chunk)

                try await embeddingPipeline.indexDocumentChunk(chunk: chunk)

                return RememberOutput(
                    documentId: documentId,
                    message: "Memory saved: \(input.label)"
                )
            }
        )
    }

    // MARK: - take_note

    public static func takeNote(
        chatMessageRepository: any ChatMessageRepoForSuggestion
    ) -> Tool<TakeNoteInput, TakeNoteOutput> {
        Tool<TakeNoteInput, TakeNoteOutput>(
            name: "take_note",
            description: "Take a note during the current meeting.",
            parameters: [
                .required("text", type: .string, description: "The note text"),
                .optional("meetingId", type: .string, description: "The meeting ID to associate the note with"),
            ],
            handler: { @Sendable input in
                let noteId = UUID().uuidString

                let message = ChatMessageRecord(
                    id: noteId,
                    role: "note",
                    content: input.text,
                    meetingId: input.meetingId,
                    createdAt: Date()
                )
                try await chatMessageRepository.create(message)

                return TakeNoteOutput(
                    noteId: noteId,
                    message: "Note saved"
                )
            }
        )
    }

    // MARK: - search_knowledge

    public static func searchKnowledge(
        embeddingEngine: any EmbeddingProviding,
        vectorSearchService: any VectorSearching,
        meetingRepository: any MeetingRepositoryProtocol,
        documentRepository: any DocumentRepositoryProtocol
    ) -> Tool<SearchInput, SearchOutput> {
        Tool<SearchInput, SearchOutput>(
            name: "search_knowledge",
            description: "Search the knowledge base for relevant information.",
            parameters: [
                .required("query", type: .string, description: "The search query"),
                .optional("limit", type: .int, description: "Maximum number of results to return"),
            ],
            handler: { @Sendable input in
                let limit = input.limit ?? 5
                let embedding = try await embeddingEngine.embed(text: input.query, mode: .query)
                let searchResults = try await vectorSearchService.search(query: embedding, limit: limit)

                var items: [SearchResultItem] = []
                for result in searchResults {
                    if let chunk = try await documentRepository.getChunk(id: result.id) {
                        items.append(SearchResultItem(
                            text: chunk.content,
                            source: "document:\(chunk.documentId)",
                            score: 1.0 - result.distance
                        ))
                    } else if let segment = try await meetingRepository.getSegment(id: result.id) {
                        items.append(SearchResultItem(
                            text: segment.text,
                            source: "meeting:\(segment.meetingId)",
                            score: 1.0 - result.distance
                        ))
                    }
                }

                return SearchOutput(results: items)
            }
        )
    }

    // MARK: - generate_summary

    public static func generateSummary(
        meetingRepository: any MeetingRepositoryProtocol,
        textGenerationEngine: any TextGenerationProviding
    ) -> Tool<SummaryInput, SummaryOutput> {
        Tool<SummaryInput, SummaryOutput>(
            name: "generate_summary",
            description: "Generate a summary of a meeting's transcript.",
            parameters: [
                .required("meetingId", type: .string, description: "The ID of the meeting to summarize")
            ],
            handler: { @Sendable input in
                let segments = try await meetingRepository.getTranscript(meetingId: input.meetingId)

                guard !segments.isEmpty else {
                    return SummaryOutput(summary: "No transcript available for this meeting.")
                }

                let transcript = segments.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")

                let systemPrompt = "You are a meeting summarizer. Generate a concise summary of the following meeting transcript."
                let prompt = "Please summarize this meeting transcript:\n\n\(transcript)"

                var summaryText = ""
                let stream = textGenerationEngine.generate(
                    prompt: prompt,
                    systemPrompt: systemPrompt,
                    maxTokens: 512
                )

                for await chunk in stream {
                    summaryText += chunk
                }

                return SummaryOutput(summary: summaryText)
            }
        )
    }
}
