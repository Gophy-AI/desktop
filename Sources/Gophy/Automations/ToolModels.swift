import Foundation

// MARK: - Remember Tool Models

public struct RememberInput: Codable, Sendable {
    public let content: String
    public let label: String
}

public struct RememberOutput: Codable, Sendable {
    public let documentId: String
    public let message: String
}

// MARK: - TakeNote Tool Models

public struct TakeNoteInput: Codable, Sendable {
    public let text: String
    public let meetingId: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        meetingId = try container.decodeIfPresent(String.self, forKey: .meetingId)
    }
}

public struct TakeNoteOutput: Codable, Sendable {
    public let noteId: String
    public let message: String
}

// MARK: - SearchKnowledge Tool Models

public struct SearchInput: Codable, Sendable {
    public let query: String
    public let limit: Int?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        query = try container.decode(String.self, forKey: .query)
        limit = try container.decodeIfPresent(Int.self, forKey: .limit)
    }
}

public struct SearchOutput: Codable, Sendable {
    public let results: [SearchResultItem]
}

public struct SearchResultItem: Codable, Sendable {
    public let text: String
    public let source: String
    public let score: Float
}

// MARK: - GenerateSummary Tool Models

public struct SummaryInput: Codable, Sendable {
    public let meetingId: String
}

public struct SummaryOutput: Codable, Sendable {
    public let summary: String
}

// MARK: - Tool Dependency Protocol

/// Protocol for document CRUD operations needed by built-in tools.
/// Kept separate from DocumentRepositoryProtocol (RAG) which only has getChunk.
public protocol DocumentRepositoryForTools: Sendable {
    func createDocument(_ document: DocumentRecord) async throws
    func addChunk(_ chunk: DocumentChunkRecord) async throws
    func deleteDocument(id: String) async throws
}
