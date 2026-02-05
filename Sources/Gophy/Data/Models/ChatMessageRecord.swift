import Foundation
import GRDB

public struct ChatMessageRecord: Codable, Sendable {
    public let id: String
    public let role: String
    public let content: String
    public let meetingId: String?
    public let createdAt: Date

    public init(
        id: String,
        role: String,
        content: String,
        meetingId: String?,
        createdAt: Date
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.meetingId = meetingId
        self.createdAt = createdAt
    }
}

extension ChatMessageRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "chat_messages"
}
