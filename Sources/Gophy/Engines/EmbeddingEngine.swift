import Foundation
import MLXEmbedders
import MLX

public final class EmbeddingEngine: @unchecked Sendable {
    private var modelContainer: ModelContainer?
    private(set) public var isLoaded: Bool = false
    private let modelRegistry: any ModelRegistryProtocol

    public init(modelRegistry: any ModelRegistryProtocol = ModelRegistry.shared) {
        self.modelRegistry = modelRegistry
    }

    public func load() async throws {
        guard let embeddingModel = modelRegistry.availableModels().first(where: { $0.type == .embedding }) else {
            throw EmbeddingError.noModelAvailable
        }

        let modelPath = modelRegistry.downloadPath(for: embeddingModel)
        let configuration = ModelConfiguration(directory: modelPath)

        modelContainer = try await loadModelContainer(configuration: configuration)
        isLoaded = true
    }

    public func embed(text: String) async throws -> [Float] {
        guard let modelContainer else {
            throw EmbeddingError.modelNotLoaded
        }

        guard !text.isEmpty else {
            throw EmbeddingError.emptyInput
        }

        let embedding = await modelContainer.perform { model, tokenizer, pooler in
            let tokens = tokenizer.encode(text: text)
            let inputIds = MLXArray(tokens)
            let batchedInputIds = inputIds.reshaped([1, tokens.count])

            let output = model(batchedInputIds, positionIds: nil, tokenTypeIds: nil, attentionMask: nil)
            let pooled = pooler(output, normalize: true)

            eval(pooled)

            return pooled.asArray(Float.self)
        }

        return embedding
    }

    public func embedBatch(texts: [String]) async throws -> [[Float]] {
        guard modelContainer != nil else {
            throw EmbeddingError.modelNotLoaded
        }

        var results: [[Float]] = []
        for text in texts {
            let embedding = try await embed(text: text)
            results.append(embedding)
        }
        return results
    }

    public func unload() {
        modelContainer = nil
        isLoaded = false
    }
}

public enum EmbeddingError: Error, Sendable {
    case modelNotLoaded
    case emptyInput
    case noModelAvailable
}
