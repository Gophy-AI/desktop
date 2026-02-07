import Testing
import Foundation
@testable import Gophy

@Suite("LocalTextGenerationProvider Tests")
struct LocalTextGenerationProviderTests {

    @Test("Conforms to TextGenerationProvider protocol")
    func testProtocolConformance() async {
        let mockEngine = StubTextGenerationEngine()
        let provider: any TextGenerationProvider = LocalTextGenerationProvider(engine: mockEngine)
        _ = provider
    }

    @Test("Generate returns streaming tokens from underlying engine")
    func testGenerateStreamsTokens() async throws {
        let mockEngine = StubTextGenerationEngine()
        mockEngine.tokensToReturn = ["Hello", " world", "!"]
        mockEngine.simulateLoaded = true

        let provider = LocalTextGenerationProvider(engine: mockEngine)

        var collected: [String] = []
        let stream = provider.generate(prompt: "Hi", systemPrompt: "", maxTokens: 100, temperature: 0.7)
        for try await token in stream {
            collected.append(token)
        }

        #expect(collected == ["Hello", " world", "!"])
    }

    @Test("Unloaded engine throws ProviderError.notConfigured")
    func testUnloadedEngineThrows() async {
        let mockEngine = StubTextGenerationEngine()
        mockEngine.simulateLoaded = false

        let provider = LocalTextGenerationProvider(engine: mockEngine)

        var caughtError: ProviderError?
        let stream = provider.generate(prompt: "Hi", systemPrompt: "", maxTokens: 100, temperature: 0.7)
        do {
            for try await _ in stream {
                // Should not yield any tokens
            }
        } catch let error as ProviderError {
            caughtError = error
        } catch {
            // Unexpected error type
        }

        if case .notConfigured = caughtError {
            // Expected
        } else {
            Issue.record("Expected ProviderError.notConfigured, got \(String(describing: caughtError))")
        }
    }
}

final class StubTextGenerationEngine: TextGenerationCapable, @unchecked Sendable {
    var loadCalled = false
    var simulateLoaded = false
    var tokensToReturn: [String] = []

    var isLoaded: Bool { simulateLoaded }

    func load() async throws {
        loadCalled = true
        simulateLoaded = true
    }

    func unload() {
        simulateLoaded = false
    }

    func generate(prompt: String, systemPrompt: String, maxTokens: Int) -> AsyncStream<String> {
        let tokens = tokensToReturn
        let loaded = simulateLoaded
        return AsyncStream { continuation in
            if !loaded {
                continuation.finish()
                return
            }
            for token in tokens {
                continuation.yield(token)
            }
            continuation.finish()
        }
    }
}
