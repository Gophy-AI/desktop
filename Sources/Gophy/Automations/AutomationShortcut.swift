import AppKit
import Foundation

/// Defines a keyboard shortcut that triggers an automation tool.
public struct AutomationShortcut: Sendable {
    /// The key equivalent (lowercase letter) for the shortcut.
    public let keyEquivalent: String

    /// The modifier flags required (e.g., .command, .shift).
    public let modifiers: NSEvent.ModifierFlags

    /// The name of the tool to trigger.
    public let toolName: String

    /// Function to build tool arguments from the current meeting ID.
    public let buildArgs: @Sendable (String) -> [String: String]

    /// A human-readable description of the shortcut.
    public let description: String

    public init(
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags,
        toolName: String,
        buildArgs: @Sendable @escaping (String) -> [String: String],
        description: String
    ) {
        self.keyEquivalent = keyEquivalent
        self.modifiers = modifiers
        self.toolName = toolName
        self.buildArgs = buildArgs
        self.description = description
    }
}

// MARK: - Default Shortcuts

extension AutomationShortcut {

    /// Default keyboard shortcuts for built-in automation tools.
    public static var defaults: [AutomationShortcut] {
        [
            rememberShortcut,
            takeNoteShortcut,
            summaryShortcut,
            searchShortcut,
        ]
    }

    /// Cmd+Shift+R -> remember
    public static var rememberShortcut: AutomationShortcut {
        AutomationShortcut(
            keyEquivalent: "r",
            modifiers: [.command, .shift],
            toolName: "remember",
            buildArgs: { meetingId in ["meetingId": meetingId] },
            description: "Remember recent context (Cmd+Shift+R)"
        )
    }

    /// Cmd+Shift+N -> take_note
    public static var takeNoteShortcut: AutomationShortcut {
        AutomationShortcut(
            keyEquivalent: "n",
            modifiers: [.command, .shift],
            toolName: "take_note",
            buildArgs: { meetingId in ["meetingId": meetingId] },
            description: "Take a note (Cmd+Shift+N)"
        )
    }

    /// Cmd+Shift+S -> generate_summary
    public static var summaryShortcut: AutomationShortcut {
        AutomationShortcut(
            keyEquivalent: "s",
            modifiers: [.command, .shift],
            toolName: "generate_summary",
            buildArgs: { meetingId in ["meetingId": meetingId] },
            description: "Generate meeting summary (Cmd+Shift+S)"
        )
    }

    /// Cmd+Shift+F -> search_knowledge
    public static var searchShortcut: AutomationShortcut {
        AutomationShortcut(
            keyEquivalent: "f",
            modifiers: [.command, .shift],
            toolName: "search_knowledge",
            buildArgs: { meetingId in ["meetingId": meetingId] },
            description: "Search knowledge base (Cmd+Shift+F)"
        )
    }
}
