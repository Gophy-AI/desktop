import Foundation

/// Defines a voice command pattern that triggers an automation tool.
public struct VoicePattern: @unchecked Sendable {
    /// The regex pattern to match against transcript text.
    public let regex: Regex<AnyRegexOutput>

    /// The name of the tool to trigger when this pattern matches.
    public let toolName: String

    /// Function to extract arguments from the regex match.
    public let extractArgs: @Sendable (Regex<AnyRegexOutput>.Match) -> [String: String]

    /// A human-readable description of the voice command.
    public let description: String

    public init(
        regex: Regex<AnyRegexOutput>,
        toolName: String,
        extractArgs: @Sendable @escaping (Regex<AnyRegexOutput>.Match) -> [String: String],
        description: String
    ) {
        self.regex = regex
        self.toolName = toolName
        self.extractArgs = extractArgs
        self.description = description
    }
}

// MARK: - Default Patterns

extension VoicePattern {

    /// Default voice patterns for built-in tools.
    public static var defaults: [VoicePattern] {
        [
            rememberPattern,
            takeNotePattern,
            summarizePattern,
            searchPattern,
        ]
    }

    /// "remember this" -> triggers remember tool
    public static var rememberPattern: VoicePattern {
        VoicePattern(
            regex: try! Regex("(?i)\\b(?:hey gophy,?\\s+)?remember this\\b"),
            toolName: "remember",
            extractArgs: { _ in [:] },
            description: "Say 'remember this' to save recent context"
        )
    }

    /// "take a note" / "take note" -> triggers take_note tool
    public static var takeNotePattern: VoicePattern {
        VoicePattern(
            regex: try! Regex("(?i)\\b(?:hey gophy,?\\s+)?take (?:a )?note\\b"),
            toolName: "take_note",
            extractArgs: { _ in [:] },
            description: "Say 'take a note' to save a note"
        )
    }

    /// "summarize the meeting" / "summarize meeting" -> triggers generate_summary tool
    public static var summarizePattern: VoicePattern {
        VoicePattern(
            regex: try! Regex("(?i)\\b(?:hey gophy,?\\s+)?summarize (?:the )?meeting\\b"),
            toolName: "generate_summary",
            extractArgs: { _ in [:] },
            description: "Say 'summarize the meeting' to get a summary"
        )
    }

    /// "search for <query>" -> triggers search_knowledge tool with extracted query
    public static var searchPattern: VoicePattern {
        VoicePattern(
            regex: try! Regex("(?i)\\b(?:hey gophy,?\\s+)?search (?:for )?(.+)"),
            toolName: "search_knowledge",
            extractArgs: { match in
                // Extract the query from the capture group
                if match.output.count > 1, let substring = match.output[1].substring {
                    return ["query": String(substring)]
                }
                return [:]
            },
            description: "Say 'search for <query>' to search the knowledge base"
        )
    }
}
