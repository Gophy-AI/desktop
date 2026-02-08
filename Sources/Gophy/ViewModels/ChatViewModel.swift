import Foundation

public struct ChatMessage: Identifiable, Sendable {
    public let id: String
    public let role: String
    public let content: String
    public let createdAt: Date

    public init(id: String, role: String, content: String, createdAt: Date) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}
