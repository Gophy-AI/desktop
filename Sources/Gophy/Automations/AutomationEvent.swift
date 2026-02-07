import Foundation
import MLXLMCommon

/// Source that triggered an automation action.
public enum TriggerSource: String, Sendable, Codable {
    case voiceCommand = "voice_command"
    case keyboardShortcut = "keyboard_shortcut"
    case manual
}

/// Events emitted by the automation trigger systems.
public enum AutomationEvent: Sendable {
    /// An automation was triggered.
    case triggered(toolName: String, source: TriggerSource)

    /// A tool is being executed.
    case executing(toolName: String)

    /// A tool call completed with a result.
    case completed(toolName: String, result: String)

    /// A tool call requires user confirmation.
    case confirmationNeeded(toolCall: ToolCall)

    /// A tool call failed.
    case failed(toolName: String, error: String)
}
