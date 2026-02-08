import Foundation

public enum ChatContextType: String, Codable, Sendable {
    case all
    case meetings
    case documents
    case meeting
    case document

    public func toRAGScope(contextId: String?) -> RAGScope {
        switch self {
        case .all:
            return .all
        case .meetings:
            return .meetings
        case .documents:
            return .documents
        case .meeting:
            if let contextId {
                return .meeting(id: contextId)
            }
            return .meetings
        case .document:
            if let contextId {
                return .document(id: contextId)
            }
            return .documents
        }
    }

    public var displayIcon: String {
        switch self {
        case .all:
            return "bubble.left.and.bubble.right"
        case .meetings:
            return "person.3"
        case .documents:
            return "doc.text"
        case .meeting:
            return "person.3.fill"
        case .document:
            return "doc.text.fill"
        }
    }
}
