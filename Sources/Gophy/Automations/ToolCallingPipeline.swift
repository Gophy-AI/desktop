import Foundation
import MLXLMCommon

/// Orchestrates the generate -> tool call -> execute -> re-generate loop.
///
/// The pipeline drives multi-turn tool calling by:
/// 1. Calling `generateWithTools` with the tool schemas from ToolExecutor.
/// 2. When a `.toolCall` is emitted, checking the tool's tier for confirmation.
/// 3. Executing the tool and appending its result to the conversation.
/// 4. Re-invoking generation with the updated context (up to `maxRounds`).
public actor ToolCallingPipeline {
    private let textGenerationEngine: any TextGenerationWithToolsProviding
    private let toolExecutor: ToolExecutor
    private let confirmationHandler: any ConfirmationHandler
    private let maxRounds: Int

    public init(
        textGenerationEngine: any TextGenerationWithToolsProviding,
        toolExecutor: ToolExecutor,
        confirmationHandler: any ConfirmationHandler,
        maxRounds: Int = 3
    ) {
        self.textGenerationEngine = textGenerationEngine
        self.toolExecutor = toolExecutor
        self.confirmationHandler = confirmationHandler
        self.maxRounds = maxRounds
    }

    public func run(
        prompt: String,
        systemPrompt: String,
        meetingContext: MeetingContext?,
        maxTokens: Int
    ) -> AsyncStream<PipelineEvent> {
        let engine = textGenerationEngine
        let executor = toolExecutor
        let confirmation = confirmationHandler
        let maxRounds = self.maxRounds

        return AsyncStream { continuation in
            Task {
                var conversationMessages: [[String: String]] = []

                // Build system prompt with meeting context
                var fullSystemPrompt = systemPrompt
                if let context = meetingContext {
                    if !fullSystemPrompt.isEmpty {
                        fullSystemPrompt += "\n\n"
                    }
                    fullSystemPrompt += "Current meeting ID: \(context.meetingId)\n"
                    fullSystemPrompt += "Recent transcript:\n\(context.recentTranscript)"
                }

                if !fullSystemPrompt.isEmpty {
                    conversationMessages.append(["role": "system", "content": fullSystemPrompt])
                }
                conversationMessages.append(["role": "user", "content": prompt])

                let schemas = await executor.toolSchemas
                var roundsUsed = 0

                while roundsUsed <= maxRounds {
                    let currentPrompt = conversationMessages
                        .filter { $0["role"] == "user" || $0["role"] == "tool" }
                        .compactMap { $0["content"] }
                        .joined(separator: "\n")

                    let toolSpecs: [[String: any Sendable]]? = schemas.isEmpty ? nil : schemas
                    let stream = engine.generateWithTools(
                        prompt: currentPrompt,
                        systemPrompt: fullSystemPrompt,
                        tools: toolSpecs,
                        maxTokens: maxTokens
                    )

                    var pendingToolCall: ToolCall?

                    for await event in stream {
                        switch event {
                        case .text(let text):
                            continuation.yield(.text(text))
                        case .toolCall(let tc):
                            pendingToolCall = tc
                        case .done:
                            break
                        }
                    }

                    guard let toolCall = pendingToolCall else {
                        // No tool call - generation complete
                        break
                    }

                    roundsUsed += 1
                    if roundsUsed > maxRounds {
                        break
                    }

                    continuation.yield(.toolCallStarted(toolCall))

                    // Check tier and confirm if needed
                    let tier = await executor.tier(for: toolCall.function.name)
                    if tier == .confirm || tier == .review {
                        let approved = await confirmation.confirm(toolCall: toolCall)
                        if !approved {
                            // User denied - stop pipeline
                            break
                        }
                    }

                    // Execute the tool
                    do {
                        let result = try await executor.execute(toolCall)
                        continuation.yield(.toolCallCompleted(
                            name: toolCall.function.name,
                            result: result
                        ))

                        // Append tool result to conversation for next round
                        conversationMessages.append([
                            "role": "tool",
                            "content": "Tool \(toolCall.function.name) returned: \(result)",
                        ])
                    } catch {
                        continuation.yield(.error(error.localizedDescription))
                        break
                    }
                }

                continuation.yield(.done)
                continuation.finish()
            }
        }
    }
}
