import Foundation

/// Classification of tool actions by their risk level.
///
/// Determines whether a tool call requires user confirmation before execution.
public enum ActionTier: String, Sendable, Codable {
    /// Read-only or in-app-only actions. Execute automatically without confirmation.
    case autoExecute

    /// Actions that modify persistent state. Require user confirmation before executing.
    case confirm

    /// Actions with external side effects. Require detailed review before executing.
    case review
}
