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
        guard let textGenModel = modelRegistry.availableModels().first(where: { $0.type == .textGen }) else {
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

    public func unload() {
        modelContainer = nil
        isLoaded = false
    }
}

public enum TextGenerationError: Error, Sendable {
    case modelNotLoaded
    case modelNotFound
}
