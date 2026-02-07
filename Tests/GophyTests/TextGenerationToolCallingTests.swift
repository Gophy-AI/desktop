import Testing
import Foundation
import MLXLMCommon
@testable import Gophy

// MARK: - Mock TextGenerationEngine for Tool Calling

private final class MockTextGenEngineForToolCalling: TextGenerationWithToolsProviding, @unchecked Sendable {
    var isLoaded: Bool = true
    var generationEvents: [GenerationEvent] = []

    func generate(prompt: String, systemPrompt: String, maxTokens: Int) -> AsyncStream<String> {
        AsyncStream { continuation in
            for event in self.generationEvents {
                switch event {
                case .text(let text):
                    continuation.yield(text)
                default:
                    break
                }
            }
            continuation.finish()
        }
    }

    func generateWithTools(
        prompt: String,
        systemPrompt: String,
        tools: [[String: any Sendable]]?,
        maxTokens: Int
    ) -> AsyncStream<GenerationEvent> {
        let events = self.generationEvents
        return AsyncStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

// MARK: - Tests

@Suite("TextGenerationEngine Tool Calling")
struct TextGenerationToolCallingTests {

    @Test("generateWithTools with tools=nil yields text events only")
    func generateWithToolsNilToolsYieldsTextOnly() async throws {
        let engine = MockTextGenEngineForToolCalling()
        engine.generationEvents = [
            .text("Hello"),
            .text(" world"),
            .done,
        ]

        var collected: [GenerationEvent] = []
        let stream = engine.generateWithTools(
            prompt: "Say hello",
            systemPrompt: "",
            tools: nil,
            maxTokens: 100
        )
        for await event in stream {
            collected.append(event)
        }

        #expect(collected.count == 3)
        if case .text(let text) = collected[0] {
            #expect(text == "Hello")
        } else {
            Issue.record("Expected .text event")
        }
        if case .text(let text) = collected[1] {
            #expect(text == " world")
        } else {
            Issue.record("Expected .text event")
        }
        if case .done = collected[2] {
            // expected
        } else {
            Issue.record("Expected .done event")
        }
    }

    @Test("generateWithTools with tools yields .toolCall when model invokes one")
    func generateWithToolsYieldsToolCall() async throws {
        let toolCall = ToolCall(
            function: ToolCall.Function(
                name: "remember",
                arguments: ["content": "test" as any Sendable, "label": "test" as any Sendable]
            )
        )

        let engine = MockTextGenEngineForToolCalling()
        engine.generationEvents = [
            .text("I'll save that. "),
            .toolCall(toolCall),
            .done,
        ]

        let toolSpec: [String: any Sendable] = [
            "type": "function",
            "function": [
                "name": "remember",
                "description": "Save info",
                "parameters": [
                    "type": "object",
                    "properties": [:] as [String: any Sendable],
                    "required": [] as [String],
                ] as [String: any Sendable],
            ] as [String: any Sendable],
        ]

        var collected: [GenerationEvent] = []
        let stream = engine.generateWithTools(
            prompt: "Remember this",
            systemPrompt: "",
            tools: [toolSpec],
            maxTokens: 100
        )
        for await event in stream {
            collected.append(event)
        }

        #expect(collected.count == 3)
        if case .toolCall(let tc) = collected[1] {
            #expect(tc.function.name == "remember")
        } else {
            Issue.record("Expected .toolCall event at index 1, got \(collected[1])")
        }
    }

    @Test("generateWithTools yields .done after all events")
    func generateWithToolsYieldsDone() async throws {
        let engine = MockTextGenEngineForToolCalling()
        engine.generationEvents = [
            .text("Result"),
            .done,
        ]

        var lastEvent: GenerationEvent?
        let stream = engine.generateWithTools(
            prompt: "test",
            systemPrompt: "",
            tools: nil,
            maxTokens: 100
        )
        for await event in stream {
            lastEvent = event
        }

        if case .done = lastEvent {
            // expected
        } else {
            Issue.record("Expected last event to be .done")
        }
    }

    @Test("GenerationEvent text-only scenario contains no tool calls")
    func generationEventTextOnlyNoToolCalls() async throws {
        let engine = MockTextGenEngineForToolCalling()
        engine.generationEvents = [
            .text("Just"),
            .text(" text"),
            .done,
        ]

        var hasToolCall = false
        let stream = engine.generateWithTools(
            prompt: "test",
            systemPrompt: "",
            tools: nil,
            maxTokens: 100
        )
        for await event in stream {
            if case .toolCall = event {
                hasToolCall = true
            }
        }

        #expect(!hasToolCall)
    }

    @Test("GenerationEvent enum cases are correct")
    func generationEventCases() async throws {
        let textEvent = GenerationEvent.text("hello")
        let doneEvent = GenerationEvent.done
        let toolCallEvent = GenerationEvent.toolCall(
            ToolCall(function: ToolCall.Function(name: "test", arguments: [:]))
        )

        if case .text(let t) = textEvent {
            #expect(t == "hello")
        } else {
            Issue.record("Expected .text case")
        }

        if case .done = doneEvent {
            // expected
        } else {
            Issue.record("Expected .done case")
        }

        if case .toolCall(let tc) = toolCallEvent {
            #expect(tc.function.name == "test")
        } else {
            Issue.record("Expected .toolCall case")
        }
    }
}
