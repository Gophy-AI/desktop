import Foundation

public protocol EmbeddingCapable: EmbeddingEngineProtocol {
    func embed(text: String, mode: EmbeddingMode) async throws -> [Float]
    func embedBatch(texts: [String], mode: EmbeddingMode) async throws -> [[Float]]
}

extension EmbeddingEngine: EmbeddingCapable {}

public final class LocalEmbeddingProvider: EmbeddingProvider, @unchecked Sendable {
    private let engine: any EmbeddingCapable
    public let dimensions: Int

    public init(engine: any EmbeddingCapable, dimensions: Int = 384) {
        self.engine = engine
        self.dimensions = dimensions
    }

    public func embed(text: String) async throws -> [Float] {
        guard engine.isLoaded else {
            throw ProviderError.notConfigured
        }
        return try await engine.embed(text: text, mode: .passage)
    }

    public func embedBatch(texts: [String]) async throws -> [[Float]] {
        guard engine.isLoaded else {
            throw ProviderError.notConfigured
        }
        return try await engine.embedBatch(texts: texts, mode: .passage)
    }
}
