import Testing
import Foundation
import MLXLMCommon
@testable import Gophy

// MARK: - Test Input/Output Types

private struct EchoInput: Codable, Sendable {
    let message: String
}

private struct EchoOutput: Codable, Sendable {
    let echoed: String
}

private struct AddInput: Codable, Sendable {
    let a: Int
    let b: Int
}

private struct AddOutput: Codable, Sendable {
    let result: Int
}

// MARK: - ToolExecutor Tests

@Suite("ToolExecutor")
struct ToolExecutorTests {

    private func makeEchoTool() -> Tool<EchoInput, EchoOutput> {
        Tool<EchoInput, EchoOutput>(
            name: "echo",
            description: "Echoes the input message",
            parameters: [
                .required("message", type: .string, description: "The message to echo")
            ],
            handler: { input in
                EchoOutput(echoed: input.message)
            }
        )
    }

    private func makeAddTool() -> Tool<AddInput, AddOutput> {
        Tool<AddInput, AddOutput>(
            name: "add",
            description: "Adds two numbers",
            parameters: [
                .required("a", type: .int, description: "First number"),
                .required("b", type: .int, description: "Second number"),
            ],
            handler: { input in
                AddOutput(result: input.a + input.b)
            }
        )
    }

    @Test("registerTool adds tool to registry and schema list")
    func registerToolAddsToRegistry() async throws {
        let executor = ToolExecutor()
        let echoTool = makeEchoTool()

        try await executor.register(echoTool)

        let schemas = await executor.toolSchemas
        #expect(schemas.count == 1)

        let function = schemas[0]["function"] as? [String: any Sendable]
        let name = function?["name"] as? String
        #expect(name == "echo")
    }

    @Test("execute dispatches ToolCall to correct handler by function.name")
    func executeDispatchesToCorrectHandler() async throws {
        let executor = ToolExecutor()
        try await executor.register(makeEchoTool())
        try await executor.register(makeAddTool())

        let toolCall = ToolCall(
            function: ToolCall.Function(
                name: "echo",
                arguments: ["message": "hello" as any Sendable]
            )
        )

        let result = try await executor.execute(toolCall)
        #expect(result.contains("hello"))
    }

    @Test("execute with unknown tool name throws toolNotFound")
    func executeUnknownToolThrows() async throws {
        let executor = ToolExecutor()
        try await executor.register(makeEchoTool())

        let toolCall = ToolCall(
            function: ToolCall.Function(
                name: "nonexistent",
                arguments: ["message": "hello" as any Sendable]
            )
        )

        await #expect(throws: ToolExecutorError.self) {
            try await executor.execute(toolCall)
        }
    }

    @Test("execute with argument decode failure throws executionFailed")
    func executeDecodeFailureThrows() async throws {
        let executor = ToolExecutor()
        try await executor.register(makeAddTool())

        // Pass string arguments where integers are expected
        let toolCall = ToolCall(
            function: ToolCall.Function(
                name: "add",
                arguments: ["a": "not_a_number" as any Sendable, "b": "also_not" as any Sendable]
            )
        )

        await #expect(throws: ToolExecutorError.self) {
            try await executor.execute(toolCall)
        }
    }

    @Test("toolSchemas returns ToolSpec array matching registered tools")
    func toolSchemasReturnsCorrectArray() async throws {
        let executor = ToolExecutor()
        try await executor.register(makeEchoTool())
        try await executor.register(makeAddTool())

        let schemas = await executor.toolSchemas
        #expect(schemas.count == 2)

        let names = schemas.compactMap { schema -> String? in
            let function = schema["function"] as? [String: any Sendable]
            return function?["name"] as? String
        }
        #expect(names.contains("echo"))
        #expect(names.contains("add"))
    }

    @Test("registering two tools with same name throws duplicateName")
    func duplicateNameThrows() async throws {
        let executor = ToolExecutor()
        try await executor.register(makeEchoTool())

        await #expect(throws: ToolExecutorError.self) {
            try await executor.register(self.makeEchoTool())
        }
    }

    @Test("execute returns JSON-encoded output string")
    func executeReturnsJSONString() async throws {
        let executor = ToolExecutor()
        try await executor.register(makeAddTool())

        let toolCall = ToolCall(
            function: ToolCall.Function(
                name: "add",
                arguments: ["a": 3 as any Sendable, "b": 7 as any Sendable]
            )
        )

        let result = try await executor.execute(toolCall)
        #expect(result.contains("10"))
    }
}
