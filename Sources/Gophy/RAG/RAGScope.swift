import Foundation

public enum RAGScope: Sendable, Hashable, Equatable {
    case all
    case meetings
    case documents
    case meeting(id: String)
    case document(id: String)

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
        case .document(let id):
            return "Document: \(id)"
        }
    }
}
