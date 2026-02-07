import Foundation
import MLXEmbedders
import MLX
import os.log

private let logger = Logger(subsystem: "com.gophy.app", category: "EmbeddingEngine")

public enum EmbeddingMode: Sendable {
    case query
    case passage
}

public final class EmbeddingEngine: @unchecked Sendable {
    private var modelContainer: ModelContainer?
    private(set) public var isLoaded: Bool = false
    private let modelRegistry: any ModelRegistryProtocol
    private let crashReporter = CrashReporter.shared

    public init(modelRegistry: any ModelRegistryProtocol = ModelRegistry.shared) {
        self.modelRegistry = modelRegistry
        crashReporter.logInfo("EmbeddingEngine initialized")
    }

    public func load() async throws {
        logger.info("Loading embedding engine...")

        // Get embedding model configuration from registry using user selection
        let selectedId = UserDefaults.standard.string(forKey: "selectedEmbeddingModelId") ?? "multilingual-e5-small"
        let embeddingModels = modelRegistry.availableModels().filter { $0.type == .embedding }

        guard let embeddingModel = embeddingModels.first(where: { $0.id == selectedId })
                ?? embeddingModels.first else {
            logger.error("No embedding model configured")
            throw EmbeddingError.noModelAvailable
        }

        logger.info("Loading model: \(embeddingModel.huggingFaceID, privacy: .public)")

        // Use MLXEmbedders' built-in model configuration
        // This handles downloading, caching, and PyTorch-to-MLX conversion
        let configuration = ModelConfiguration(id: embeddingModel.huggingFaceID)

        do {
            modelContainer = try await loadModelContainer(configuration: configuration) { progress in
                logger.info("Download progress: \(Int(progress.fractionCompleted * 100))%")
            }
            isLoaded = true
            logger.info("Embedding engine loaded successfully")
        } catch {
            logger.error("Failed to load embedding model: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    public func embed(text: String, mode: EmbeddingMode = .passage) async throws -> [Float] {
        guard let modelContainer else {
            throw EmbeddingError.modelNotLoaded
        }

        guard !text.isEmpty else {
            throw EmbeddingError.emptyInput
        }

        let prefixedText: String
        switch mode {
        case .query:
            prefixedText = "query: " + text
        case .passage:
            prefixedText = "passage: " + text
        }

        let embedding = await modelContainer.perform { model, tokenizer, pooler in
            // Encode with special tokens (CLS, SEP)
            var tokens = tokenizer.encode(text: prefixedText)

            // Truncate to max position embeddings (512 for most BERT models) minus special tokens
            let maxLength = 510
            if tokens.count > maxLength {
                tokens = Array(tokens.prefix(maxLength))
            }

            guard !tokens.isEmpty else {
                return [Float](repeating: 0, count: 384) // Return zero vector for empty
            }

            let inputIds = MLXArray(tokens)
            let batchedInputIds = inputIds.reshaped([1, tokens.count])

            // Create token type IDs (all zeros for single sentence)
            let tokenTypeIds = MLXArray.zeros(like: batchedInputIds)

            // Create attention mask (all ones since no padding in single input)
            let attentionMask = MLXArray.ones(like: batchedInputIds)

            let output = model(batchedInputIds, positionIds: nil, tokenTypeIds: tokenTypeIds, attentionMask: attentionMask)
            let pooled = pooler(output, normalize: true)

            eval(pooled)

            return pooled.asArray(Float.self)
        }

        return embedding
    }

    public func embedBatch(texts: [String], mode: EmbeddingMode = .passage) async throws -> [[Float]] {
        guard modelContainer != nil else {
            throw EmbeddingError.modelNotLoaded
        }

        var results: [[Float]] = []
        for text in texts {
            let embedding = try await embed(text: text, mode: mode)
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
