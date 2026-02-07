import Foundation

public protocol TextGenerationCapable: TextGenerationEngineProtocol {
    func generate(prompt: String, systemPrompt: String, maxTokens: Int) -> AsyncStream<String>
}

extension TextGenerationEngine: TextGenerationCapable {}

public final class LocalTextGenerationProvider: TextGenerationProvider, @unchecked Sendable {
    private let engine: any TextGenerationCapable

    public init(engine: any TextGenerationCapable) {
        self.engine = engine
    }

    public func generate(
        prompt: String,
        systemPrompt: String,
        maxTokens: Int,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error> {
        let engine = self.engine
        return AsyncThrowingStream { continuation in
            guard engine.isLoaded else {
                continuation.finish(throwing: ProviderError.notConfigured)
                return
            }
            Task {
                let stream = engine.generate(prompt: prompt, systemPrompt: systemPrompt, maxTokens: maxTokens)
                for await token in stream {
                    continuation.yield(token)
                }
                continuation.finish()
            }
        }
    }
}
