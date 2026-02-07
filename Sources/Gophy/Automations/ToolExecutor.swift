import Foundation
import MLXLMCommon

// MARK: - ToolExecutorError

public enum ToolExecutorError: Error, LocalizedError, Sendable {
    case toolNotFound(name: String)
    case executionFailed(name: String, underlyingError: String)
    case duplicateName(name: String)

    public var errorDescription: String? {
        switch self {
        case .toolNotFound(let name):
            return "Tool not found: '\(name)'"
        case .executionFailed(let name, let error):
            return "Tool execution failed for '\(name)': \(error)"
        case .duplicateName(let name):
            return "A tool with name '\(name)' is already registered"
        }
    }
}

// MARK: - ToolExecutor

public actor ToolExecutor {
    private var handlers: [String: @Sendable (ToolCall) async throws -> String] = [:]
    private var schemas: [String: [String: any Sendable]] = [:]
    private var tiers: [String: ActionTier] = [:]

    public init() {}

    public func register<I: Codable & Sendable, O: Codable & Sendable>(
        _ tool: Tool<I, O>,
        tier: ActionTier = .autoExecute
    ) throws {
        let name = tool.name
        guard !name.isEmpty else {
            throw ToolExecutorError.executionFailed(name: "", underlyingError: "Tool has no name")
        }
        guard handlers[name] == nil else {
            throw ToolExecutorError.duplicateName(name: name)
        }

        let capturedTool = tool
        handlers[name] = { @Sendable toolCall in
            let output: O
            do {
                output = try await toolCall.execute(with: capturedTool)
            } catch {
                throw ToolExecutorError.executionFailed(
                    name: name,
                    underlyingError: error.localizedDescription
                )
            }
            let data = try JSONEncoder().encode(output)
            return String(data: data, encoding: .utf8) ?? "{}"
        }
        schemas[name] = tool.schema
        tiers[name] = tier
    }

    public func execute(_ toolCall: ToolCall) async throws -> String {
        let name = toolCall.function.name
        guard let handler = handlers[name] else {
            throw ToolExecutorError.toolNotFound(name: name)
        }
        return try await handler(toolCall)
    }

    public func tier(for toolName: String) -> ActionTier {
        tiers[toolName] ?? .autoExecute
    }

    public func setTier(for toolName: String, tier: ActionTier) {
        tiers[toolName] = tier
    }

    public var toolSchemas: [[String: any Sendable]] {
        Array(schemas.values)
    }
}
