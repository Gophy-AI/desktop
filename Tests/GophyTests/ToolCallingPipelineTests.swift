import Testing
import Foundation
import MLXLMCommon
@testable import Gophy

// MARK: - Mocks for Pipeline Tests

private final class MockTextGenWithTools: TextGenerationWithToolsProviding, @unchecked Sendable {
    var isLoaded: Bool = true
    var callCount = 0
    var generateResults: [([GenerationEvent])] = []

    func generate(prompt: String, systemPrompt: String, maxTokens: Int) -> AsyncStream<String> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func generateWithTools(
        prompt: String,
        systemPrompt: String,
        tools: [[String: any Sendable]]?,
        maxTokens: Int
    ) -> AsyncStream<GenerationEvent> {
        let index = callCount
        callCount += 1
        let events = index < generateResults.count ? generateResults[index] : [.done]
        return AsyncStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

private actor MockToolExecutorForPipeline {
    var registeredToolNames: [String] = []
    var executeResults: [String: String] = [:]
    var executeError: Error?
    var tiers: [String: ActionTier] = [:]
    var executeCalled: [(name: String, args: [String: JSONValue])] = []

    func setResult(for name: String, result: String) {
        executeResults[name] = result
    }

    func setError(_ error: Error) {
        executeError = error
    }

    func setTier(for name: String, tier: ActionTier) {
        tiers[name] = tier
    }
}

private actor MockConfirmationHandlerForPipeline: ConfirmationHandler {
    var shouldConfirm: Bool = true
    var confirmCalled = false

    func confirm(toolCall: ToolCall) async -> Bool {
        confirmCalled = true
        return shouldConfirm
    }

    func setConfirm(_ value: Bool) {
        shouldConfirm = value
    }
}

// MARK: - Pipeline Tests

@Suite("ToolCallingPipeline")
struct ToolCallingPipelineTests {

    @Test("single-turn text-only returns text directly")
    func singleTurnTextOnly() async throws {
        let textGen = MockTextGenWithTools()
        textGen.generateResults = [
            [.text("Hello"), .text(" world"), .done],
        ]

        let executor = ToolExecutor()
        let confirmation = MockConfirmationHandlerForPipeline()

        let pipeline = ToolCallingPipeline(
            textGenerationEngine: textGen,
            toolExecutor: executor,
            confirmationHandler: confirmation,
            maxRounds: 3
        )

        var textParts: [String] = []
        var gotDone = false

        let stream = await pipeline.run(
            prompt: "Say hello",
            systemPrompt: "",
            meetingContext: nil,
            maxTokens: 100
        )

        for await event in stream {
            switch event {
            case .text(let t):
                textParts.append(t)
            case .done:
                gotDone = true
            default:
                break
            }
        }

        #expect(textParts == ["Hello", " world"])
        #expect(gotDone)
    }

    @Test("tool call triggers execution and re-generation with result")
    func toolCallTriggersExecution() async throws {
        let rememberCall = ToolCall(
            function: ToolCall.Function(
                name: "take_note",
                arguments: ["text": "test note" as any Sendable]
            )
        )

        let textGen = MockTextGenWithTools()
        textGen.generateResults = [
            // First round: model emits a tool call
            [.text("Let me help. "), .toolCall(rememberCall), .done],
            // Second round: model emits final text after getting tool result
            [.text("Done!"), .done],
        ]

        let executor = ToolExecutor()

        // Register a simple take_note tool
        let tool = Tool<TakeNoteTestInput, TakeNoteTestOutput>(
            name: "take_note",
            description: "Take a note",
            parameters: [
                .required("text", type: .string, description: "Note text"),
            ],
            handler: { input in
                TakeNoteTestOutput(noteId: "note-1", message: "Saved")
            }
        )
        try await executor.register(tool)
        await executor.setTier(for: "take_note", tier: .autoExecute)

        let confirmation = MockConfirmationHandlerForPipeline()

        let pipeline = ToolCallingPipeline(
            textGenerationEngine: textGen,
            toolExecutor: executor,
            confirmationHandler: confirmation,
            maxRounds: 3
        )

        var events: [PipelineEvent] = []
        let stream = await pipeline.run(
            prompt: "Take a note",
            systemPrompt: "",
            meetingContext: nil,
            maxTokens: 100
        )

        for await event in stream {
            events.append(event)
        }

        // Should have text from both rounds, tool call events, and done
        let textEvents = events.compactMap { event -> String? in
            if case .text(let t) = event { return t }
            return nil
        }
        #expect(textEvents.contains("Let me help. "))
        #expect(textEvents.contains("Done!"))

        let toolStarted = events.contains { event in
            if case .toolCallStarted(let tc) = event { return tc.function.name == "take_note" }
            return false
        }
        #expect(toolStarted)

        let toolCompleted = events.contains { event in
            if case .toolCallCompleted(let name, _) = event { return name == "take_note" }
            return false
        }
        #expect(toolCompleted)
    }

    @Test("maxRounds=1 stops after first tool call")
    func maxRoundsLimitsLoop() async throws {
        let toolCall = ToolCall(
            function: ToolCall.Function(
                name: "take_note",
                arguments: ["text": "test" as any Sendable]
            )
        )

        let textGen = MockTextGenWithTools()
        textGen.generateResults = [
            [.toolCall(toolCall), .done],
            // Second round should not be reached
            [.toolCall(toolCall), .done],
        ]

        let executor = ToolExecutor()
        let tool = Tool<TakeNoteTestInput, TakeNoteTestOutput>(
            name: "take_note",
            description: "Take a note",
            parameters: [
                .required("text", type: .string, description: "Note text"),
            ],
            handler: { _ in TakeNoteTestOutput(noteId: "n-1", message: "ok") }
        )
        try await executor.register(tool)
        await executor.setTier(for: "take_note", tier: .autoExecute)

        let confirmation = MockConfirmationHandlerForPipeline()

        let pipeline = ToolCallingPipeline(
            textGenerationEngine: textGen,
            toolExecutor: executor,
            confirmationHandler: confirmation,
            maxRounds: 1
        )

        var doneCount = 0
        let stream = await pipeline.run(
            prompt: "test",
            systemPrompt: "",
            meetingContext: nil,
            maxTokens: 100
        )
        for await event in stream {
            if case .done = event { doneCount += 1 }
        }

        // Should have completed with exactly 1 generation call (+ 1 re-generation after tool = 2 total)
        // But maxRounds=1 means only 1 tool call round is allowed
        #expect(doneCount == 1)
        #expect(textGen.callCount <= 2)
    }

    @Test("tool execution error returns error message, not crash")
    func toolExecutionErrorHandled() async throws {
        let toolCall = ToolCall(
            function: ToolCall.Function(
                name: "nonexistent_tool",
                arguments: [:]
            )
        )

        let textGen = MockTextGenWithTools()
        textGen.generateResults = [
            [.toolCall(toolCall), .done],
            [.text("Recovered"), .done],
        ]

        let executor = ToolExecutor()
        // Don't register any tools, so execution will fail
        let confirmation = MockConfirmationHandlerForPipeline()

        let pipeline = ToolCallingPipeline(
            textGenerationEngine: textGen,
            toolExecutor: executor,
            confirmationHandler: confirmation,
            maxRounds: 3
        )

        var hasError = false
        var hasDone = false
        let stream = await pipeline.run(
            prompt: "test",
            systemPrompt: "",
            meetingContext: nil,
            maxTokens: 100
        )
        for await event in stream {
            if case .error = event { hasError = true }
            if case .done = event { hasDone = true }
        }

        #expect(hasError)
        #expect(hasDone)
    }

    @Test("tier 2 tool pauses for confirmation")
    func tier2PausesForConfirmation() async throws {
        let toolCall = ToolCall(
            function: ToolCall.Function(
                name: "remember",
                arguments: ["content": "data" as any Sendable, "label": "test" as any Sendable]
            )
        )

        let textGen = MockTextGenWithTools()
        textGen.generateResults = [
            [.toolCall(toolCall), .done],
            [.text("Saved!"), .done],
        ]

        let executor = ToolExecutor()
        let tool = Tool<RememberTestInput, RememberTestOutput>(
            name: "remember",
            description: "Remember info",
            parameters: [
                .required("content", type: .string, description: "Content"),
                .required("label", type: .string, description: "Label"),
            ],
            handler: { input in
                RememberTestOutput(documentId: "doc-1", message: "Remembered")
            }
        )
        try await executor.register(tool)
        await executor.setTier(for: "remember", tier: .confirm)

        let confirmation = MockConfirmationHandlerForPipeline()
        await confirmation.setConfirm(true)

        let pipeline = ToolCallingPipeline(
            textGenerationEngine: textGen,
            toolExecutor: executor,
            confirmationHandler: confirmation,
            maxRounds: 3
        )

        var events: [PipelineEvent] = []
        let stream = await pipeline.run(
            prompt: "Remember this",
            systemPrompt: "",
            meetingContext: nil,
            maxTokens: 100
        )
        for await event in stream {
            events.append(event)
        }

        let confirmed = await confirmation.confirmCalled
        #expect(confirmed)

        let completed = events.contains { event in
            if case .toolCallCompleted(let name, _) = event { return name == "remember" }
            return false
        }
        #expect(completed)
    }

    @Test("tier 1 tool auto-executes without confirmation")
    func tier1AutoExecutes() async throws {
        let toolCall = ToolCall(
            function: ToolCall.Function(
                name: "take_note",
                arguments: ["text": "auto note" as any Sendable]
            )
        )

        let textGen = MockTextGenWithTools()
        textGen.generateResults = [
            [.toolCall(toolCall), .done],
            [.text("Noted."), .done],
        ]

        let executor = ToolExecutor()
        let tool = Tool<TakeNoteTestInput, TakeNoteTestOutput>(
            name: "take_note",
            description: "Take a note",
            parameters: [
                .required("text", type: .string, description: "Note text"),
            ],
            handler: { _ in TakeNoteTestOutput(noteId: "n-1", message: "ok") }
        )
        try await executor.register(tool)
        await executor.setTier(for: "take_note", tier: .autoExecute)

        let confirmation = MockConfirmationHandlerForPipeline()

        let pipeline = ToolCallingPipeline(
            textGenerationEngine: textGen,
            toolExecutor: executor,
            confirmationHandler: confirmation,
            maxRounds: 3
        )

        let stream = await pipeline.run(
            prompt: "Take a note",
            systemPrompt: "",
            meetingContext: nil,
            maxTokens: 100
        )
        for await _ in stream {}

        let confirmCalled = await confirmation.confirmCalled
        #expect(!confirmCalled)
    }

    @Test("confirmation denied skips tool execution")
    func confirmationDeniedSkipsTool() async throws {
        let toolCall = ToolCall(
            function: ToolCall.Function(
                name: "remember",
                arguments: ["content": "data" as any Sendable, "label": "test" as any Sendable]
            )
        )

        let textGen = MockTextGenWithTools()
        textGen.generateResults = [
            [.toolCall(toolCall), .done],
        ]

        let executor = ToolExecutor()
        let tool = Tool<RememberTestInput, RememberTestOutput>(
            name: "remember",
            description: "Remember info",
            parameters: [
                .required("content", type: .string, description: "Content"),
                .required("label", type: .string, description: "Label"),
            ],
            handler: { _ in RememberTestOutput(documentId: "doc-1", message: "ok") }
        )
        try await executor.register(tool)
        await executor.setTier(for: "remember", tier: .confirm)

        let confirmation = MockConfirmationHandlerForPipeline()
        await confirmation.setConfirm(false)

        let pipeline = ToolCallingPipeline(
            textGenerationEngine: textGen,
            toolExecutor: executor,
            confirmationHandler: confirmation,
            maxRounds: 3
        )

        var toolCompleted = false
        let stream = await pipeline.run(
            prompt: "Remember",
            systemPrompt: "",
            meetingContext: nil,
            maxTokens: 100
        )
        for await event in stream {
            if case .toolCallCompleted = event { toolCompleted = true }
        }

        #expect(!toolCompleted)
    }
}

// MARK: - Test Input/Output Types

private struct TakeNoteTestInput: Codable, Sendable {
    let text: String
}

private struct TakeNoteTestOutput: Codable, Sendable {
    let noteId: String
    let message: String
}

private struct RememberTestInput: Codable, Sendable {
    let content: String
    let label: String
}

private struct RememberTestOutput: Codable, Sendable {
    let documentId: String
    let message: String
}
