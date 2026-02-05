import Foundation

public enum RAGScope: Sendable, Hashable, Equatable {
    case all
    case meetings
    case documents
    case meeting(id: String)

    public var displayName: String {
        switch self {
        case .all:
            return "All"
        case .meetings:
            return "Meetings"
        case .documents:
            return "Documents"
        case .meeting(let id):
            return "Meeting: \(id)"
        }
    }
}
