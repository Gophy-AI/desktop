import Foundation
import MLXLMCommon

/// Events emitted by TextGenerationEngine's tool-calling generation method.
public enum GenerationEvent: Sendable {
    /// A regular text chunk from the model.
    case text(String)

    /// The model requested a tool call.
    case toolCall(ToolCall)

    /// Generation is complete.
    case done
}

/// Protocol for engines that support tool-calling generation in addition to plain text generation.
public protocol TextGenerationWithToolsProviding: TextGenerationProviding {
    func generateWithTools(
        prompt: String,
        systemPrompt: String,
        tools: [[String: any Sendable]]?,
        maxTokens: Int
    ) -> AsyncStream<GenerationEvent>
}
