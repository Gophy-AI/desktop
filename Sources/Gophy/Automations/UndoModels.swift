import Foundation

/// An entry in the undo stack representing a reversible automation action.
public struct UndoEntry: Sendable {
    /// Unique identifier for this undo entry.
    public let id: String

    /// Name of the tool that was executed.
    public let toolName: String

    /// Human-readable description of the undo action.
    public let description: String

    /// When the original action was executed.
    public let timestamp: Date

    /// The closure that reverses the action.
    public let undoAction: @Sendable () async throws -> Void

    public init(
        id: String,
        toolName: String,
        description: String,
        timestamp: Date,
        undoAction: @Sendable @escaping () async throws -> Void
    ) {
        self.id = id
        self.toolName = toolName
        self.description = description
        self.timestamp = timestamp
        self.undoAction = undoAction
    }
}

/// Result returned after a successful undo operation.
public struct UndoResult: Sendable {
    /// Name of the tool whose action was undone.
    public let toolName: String

    /// Human-readable description of what was undone.
    public let description: String

    public init(toolName: String, description: String) {
        self.toolName = toolName
        self.description = description
    }
}

/// Errors that can occur during undo operations.
public enum UndoError: Error, LocalizedError, Sendable, Equatable {
    case emptyStack
    case undoFailed(toolName: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .emptyStack:
            return "Nothing to undo"
        case .undoFailed(let name, let reason):
            return "Failed to undo '\(name)': \(reason)"
        }
    }
}
