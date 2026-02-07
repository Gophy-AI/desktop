import Testing
import Foundation
@testable import Gophy

@Suite("LocalEmbeddingProvider Tests")
struct LocalEmbeddingProviderTests {

    @Test("Conforms to EmbeddingProvider protocol")
    func testProtocolConformance() async {
        let mockEngine = StubEmbeddingEngine()
        let provider: any EmbeddingProvider = LocalEmbeddingProvider(engine: mockEngine, dimensions: 384)
        _ = provider
    }

    @Test("Embed returns correct dimension vector")
    func testEmbed() async throws {
        let mockEngine = StubEmbeddingEngine()
        mockEngine.simulateLoaded = true
        mockEngine.embeddingToReturn = [Float](repeating: 0.1, count: 384)

        let provider = LocalEmbeddingProvider(engine: mockEngine, dimensions: 384)
        let result = try await provider.embed(text: "test input")

        #expect(result.count == 384)
        #expect(result[0] == 0.1)
    }

    @Test("EmbedBatch returns correct number of results")
    func testEmbedBatch() async throws {
        let mockEngine = StubEmbeddingEngine()
        mockEngine.simulateLoaded = true
        mockEngine.embeddingToReturn = [Float](repeating: 0.2, count: 384)

        let provider = LocalEmbeddingProvider(engine: mockEngine, dimensions: 384)
        let results = try await provider.embedBatch(texts: ["text1", "text2", "text3"])

        #expect(results.count == 3)
        for result in results {
            #expect(result.count == 384)
        }
    }

    @Test("Dimensions property returns correct value")
    func testDimensions() {
        let mockEngine = StubEmbeddingEngine()
        let provider = LocalEmbeddingProvider(engine: mockEngine, dimensions: 384)
        #expect(provider.dimensions == 384)
    }

    @Test("Unloaded engine throws ProviderError.notConfigured")
    func testUnloadedEngineThrows() async {
        let mockEngine = StubEmbeddingEngine()
        mockEngine.simulateLoaded = false

        let provider = LocalEmbeddingProvider(engine: mockEngine, dimensions: 384)

        do {
            _ = try await provider.embed(text: "test")
            Issue.record("Expected error to be thrown")
        } catch let error as ProviderError {
            if case .notConfigured = error {
                // Expected
            } else {
                Issue.record("Expected ProviderError.notConfigured, got \(error)")
            }
        } catch {
            Issue.record("Expected ProviderError, got \(error)")
        }
    }
}

final class StubEmbeddingEngine: EmbeddingCapable, @unchecked Sendable {
    var loadCalled = false
    var simulateLoaded = false
    var embeddingToReturn: [Float] = [Float](repeating: 0, count: 384)

    var isLoaded: Bool { simulateLoaded }
    var embeddingDimension: Int = 384

    func load() async throws {
        loadCalled = true
        simulateLoaded = true
    }

    func unload() {
        simulateLoaded = false
    }

    func embed(text: String, mode: EmbeddingMode) async throws -> [Float] {
        guard simulateLoaded else {
            throw EmbeddingError.modelNotLoaded
        }
        return embeddingToReturn
    }

    func embedBatch(texts: [String], mode: EmbeddingMode) async throws -> [[Float]] {
        guard simulateLoaded else {
            throw EmbeddingError.modelNotLoaded
        }
        return texts.map { _ in embeddingToReturn }
    }
}
