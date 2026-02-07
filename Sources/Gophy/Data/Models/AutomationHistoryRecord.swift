import Foundation
import GRDB

public struct AutomationHistoryRecord: Codable, Sendable, Identifiable {
    public let id: String
    public let toolName: String
    public let arguments: String
    public let result: String?
    public let status: String
    public let triggerSource: String
    public let meetingId: String?
    public let createdAt: Date

    public init(
        id: String,
        toolName: String,
        arguments: String,
        result: String?,
        status: String,
        triggerSource: String,
        meetingId: String?,
        createdAt: Date
    ) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
        self.result = result
        self.status = status
        self.triggerSource = triggerSource
        self.meetingId = meetingId
        self.createdAt = createdAt
    }
}

extension AutomationHistoryRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "automation_history"
}
