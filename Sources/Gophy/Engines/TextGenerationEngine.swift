import Foundation
import MLXLLM
import MLXLMCommon

public final class TextGenerationEngine: @unchecked Sendable {
    private var modelContainer: ModelContainer?
    private(set) public var isLoaded: Bool = false
    private let modelRegistry: any ModelRegistryProtocol

    public init(modelRegistry: any ModelRegistryProtocol = ModelRegistry.shared) {
        self.modelRegistry = modelRegistry
    }

    public func load() async throws {
        let selectedId = UserDefaults.standard.string(forKey: "selectedTextGenModelId") ?? "qwen2.5-7b-instruct-4bit"
        let textGenModels = modelRegistry.availableModels().filter { $0.type == .textGen }

        guard let textGenModel = textGenModels.first(where: { $0.id == selectedId && modelRegistry.isDownloaded($0) })
                ?? textGenModels.first(where: { modelRegistry.isDownloaded($0) })
                ?? textGenModels.first else {
            throw TextGenerationError.modelNotFound
        }

        let modelPath = modelRegistry.downloadPath(for: textGenModel)
        let configuration = ModelConfiguration(directory: modelPath)

        modelContainer = try await loadModelContainer(configuration: configuration)
        isLoaded = true
    }

    public func generate(
        prompt: String,
        systemPrompt: String = "",
        maxTokens: Int = 512
    ) -> AsyncStream<String> {
        AsyncStream { continuation in
            guard let modelContainer else {
                continuation.finish()
                return
            }

            Task {
                do {
                    let messages: [[String: String]]
                    if systemPrompt.isEmpty {
                        messages = [["role": "user", "content": prompt]]
                    } else {
                        messages = [
                            ["role": "system", "content": systemPrompt],
                            ["role": "user", "content": prompt]
                        ]
                    }

                    let input = try await modelContainer.prepare(input: .init(messages: messages))

                    let parameters = GenerateParameters(
                        maxTokens: maxTokens,
                        temperature: 0.7
                    )

                    var tokenCount = 0

                    let stream = try await modelContainer.generate(
                        input: input,
                        parameters: parameters
                    )

                    for await generation in stream {
                        switch generation {
                        case .chunk(let text):
                            continuation.yield(text)
                            tokenCount += 1
                            if tokenCount >= maxTokens {
                                continuation.finish()
                                return
                            }
                        case .info:
                            break
                        case .toolCall:
                            break
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
        }
    }

    public func generateWithTools(
        prompt: String,
        systemPrompt: String = "",
        tools: [[String: any Sendable]]? = nil,
        maxTokens: Int = 512
    ) -> AsyncStream<GenerationEvent> {
        AsyncStream { continuation in
            guard let modelContainer else {
                continuation.yield(.done)
                continuation.finish()
                return
            }

            Task {
                do {
                    let messages: [[String: String]]
                    if systemPrompt.isEmpty {
                        messages = [["role": "user", "content": prompt]]
                    } else {
                        messages = [
                            ["role": "system", "content": systemPrompt],
                            ["role": "user", "content": prompt],
                        ]
                    }

                    let userInput = UserInput(messages: messages, tools: tools)
                    let input = try await modelContainer.prepare(input: userInput)

                    let parameters = GenerateParameters(
                        maxTokens: maxTokens,
                        temperature: 0.7
                    )

                    var tokenCount = 0

                    let stream = try await modelContainer.generate(
                        input: input,
                        parameters: parameters
                    )

                    for await generation in stream {
                        switch generation {
                        case .chunk(let text):
                            continuation.yield(.text(text))
                            tokenCount += 1
                            if tokenCount >= maxTokens {
                                continuation.yield(.done)
                                continuation.finish()
                                return
                            }
                        case .toolCall(let toolCall):
                            continuation.yield(.toolCall(toolCall))
                        case .info:
                            break
                        }
                    }

                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    continuation.yield(.done)
                    continuation.finish()
                }
            }
        }
    }

    public func unload() {
        modelContainer = nil
        isLoaded = false
    }
}

extension TextGenerationEngine: TextGenerationWithToolsProviding {}

public enum TextGenerationError: Error, Sendable {
    case modelNotLoaded
    case modelNotFound
}
