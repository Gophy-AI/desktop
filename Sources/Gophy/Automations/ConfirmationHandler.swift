import Foundation
import MLXLMCommon

/// Protocol for handling user confirmation of tool calls that require approval.
public protocol ConfirmationHandler: Sendable {
    /// Ask the user to confirm a tool call.
    /// - Parameter toolCall: The tool call to confirm.
    /// - Returns: `true` if the user approves, `false` if denied.
    func confirm(toolCall: ToolCall) async -> Bool
}

/// A confirmation handler that auto-approves all tool calls.
/// Used as a default when no UI confirmation is needed.
public final class AutoApproveConfirmationHandler: ConfirmationHandler, Sendable {
    public init() {}

    public func confirm(toolCall: ToolCall) async -> Bool {
        true
    }
}
