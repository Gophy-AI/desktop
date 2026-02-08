import Foundation
import GRDB

public struct ChatRecord: Codable, Sendable, Identifiable {
    public let id: String
    public var title: String
    public let contextType: String
    public let contextId: String?
    public let isPredefined: Bool
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        title: String,
        contextType: String,
        contextId: String?,
        isPredefined: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.contextType = contextType
        self.contextId = contextId
        self.isPredefined = isPredefined
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var chatContextType: ChatContextType? {
        ChatContextType(rawValue: contextType)
    }

    public var ragScope: RAGScope {
        let type = chatContextType ?? .all
        return type.toRAGScope(contextId: contextId)
    }
}

extension ChatRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "chats"
}
