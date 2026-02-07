import Testing
import Foundation
@testable import Gophy

@Suite("AnthropicProvider Tests")
struct AnthropicProviderTests {

    // MARK: - Protocol Conformance

    @Test("Conforms to TextGenerationProvider protocol")
    func testTextGenerationConformance() {
        let provider: any TextGenerationProvider = makeProvider()
        _ = provider
    }

    @Test("Conforms to VisionProvider protocol")
    func testVisionConformance() {
        let provider: any VisionProvider = makeProvider()
        _ = provider
    }

    // MARK: - TextGenerationProvider

    @Test("Generate returns streaming tokens")
    func testGenerateStreaming() async throws {
        let mockSession = MockAnthropicSession()
        mockSession.streamTokens = ["Hello", " world", "!"]

        let provider = AnthropicProvider(
            apiKey: "sk-ant-test",
            textGenModel: "claude-sonnet-4-5-20250929",
            visionModel: "claude-sonnet-4-5-20250929",
            session: mockSession
        )

        var tokens: [String] = []
        let stream = provider.generate(prompt: "Hi", systemPrompt: "Be helpful", maxTokens: 100, temperature: 0.7)
        for try await token in stream {
            tokens.append(token)
        }

        #expect(tokens == ["Hello", " world", "!"])
    }

    @Test("Generate uses system prompt separately from messages")
    func testGenerateSystemPrompt() async throws {
        let mockSession = MockAnthropicSession()
        mockSession.streamTokens = ["ok"]

        let provider = AnthropicProvider(
            apiKey: "sk-ant-test",
            textGenModel: "claude-sonnet-4-5-20250929",
            visionModel: "claude-sonnet-4-5-20250929",
            session: mockSession
        )

        var tokens: [String] = []
        let stream = provider.generate(prompt: "test", systemPrompt: "system instructions", maxTokens: 50, temperature: 0.5)
        for try await token in stream {
            tokens.append(token)
        }

        #expect(mockSession.lastSystemPrompt == "system instructions")
        #expect(mockSession.lastModel == "claude-sonnet-4-5-20250929")
        #expect(mockSession.lastMaxTokens == 50)
        #expect(mockSession.lastTemperature == 0.5)
    }

    @Test("Generate with empty system prompt omits system parameter")
    func testGenerateEmptySystemPrompt() async throws {
        let mockSession = MockAnthropicSession()
        mockSession.streamTokens = ["ok"]

        let provider = AnthropicProvider(
            apiKey: "sk-ant-test",
            textGenModel: "claude-sonnet-4-5-20250929",
            visionModel: "claude-sonnet-4-5-20250929",
            session: mockSession
        )

        var tokens: [String] = []
        let stream = provider.generate(prompt: "test", systemPrompt: "", maxTokens: 100, temperature: 0.7)
        for try await token in stream {
            tokens.append(token)
        }

        #expect(mockSession.lastSystemPrompt == nil)
    }

    // MARK: - VisionProvider

    @Test("ExtractText returns vision result")
    func testExtractText() async throws {
        let mockSession = MockAnthropicSession()
        mockSession.messageResult = "Extracted text from the image"

        let provider = AnthropicProvider(
            apiKey: "sk-ant-test",
            textGenModel: "claude-sonnet-4-5-20250929",
            visionModel: "claude-sonnet-4-5-20250929",
            session: mockSession
        )

        let result = try await provider.extractText(from: Data([0xFF, 0xD8]), prompt: "Extract text")
        #expect(result == "Extracted text from the image")
    }

    @Test("AnalyzeImage returns streaming tokens")
    func testAnalyzeImage() async throws {
        let mockSession = MockAnthropicSession()
        mockSession.streamTokens = ["I see", " a cat"]

        let provider = AnthropicProvider(
            apiKey: "sk-ant-test",
            textGenModel: "claude-sonnet-4-5-20250929",
            visionModel: "claude-sonnet-4-5-20250929",
            session: mockSession
        )

        var tokens: [String] = []
        let stream = provider.analyzeImage(imageData: Data([0xFF, 0xD8]), prompt: "Describe")
        for try await token in stream {
            tokens.append(token)
        }

        #expect(tokens == ["I see", " a cat"])
    }

    @Test("ExtractText sends image as base64")
    func testExtractTextImageEncoding() async throws {
        let mockSession = MockAnthropicSession()
        mockSession.messageResult = "ok"

        let provider = AnthropicProvider(
            apiKey: "sk-ant-test",
            textGenModel: "claude-sonnet-4-5-20250929",
            visionModel: "claude-sonnet-4-5-20250929",
            session: mockSession
        )

        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        _ = try await provider.extractText(from: imageData, prompt: "test")

        #expect(mockSession.lastImageBase64 != nil)
        #expect(mockSession.lastImageBase64 == imageData.base64EncodedString())
    }

    // MARK: - Error Handling

    @Test("Rate limit error (429) throws rateLimited")
    func testRateLimitError() async {
        let mockSession = MockAnthropicSession()
        mockSession.errorToThrow = MockAnthropicError.httpError(statusCode: 429, message: "Rate limit exceeded")

        let provider = AnthropicProvider(
            apiKey: "sk-ant-test",
            textGenModel: "claude-sonnet-4-5-20250929",
            visionModel: "claude-sonnet-4-5-20250929",
            session: mockSession
        )

        do {
            _ = try await provider.extractText(from: Data(), prompt: "test")
            Issue.record("Expected error")
        } catch let error as ProviderError {
            if case .rateLimited = error {} else {
                Issue.record("Expected ProviderError.rateLimited, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Invalid API key (401) throws invalidAPIKey")
    func testInvalidAPIKeyError() async {
        let mockSession = MockAnthropicSession()
        mockSession.errorToThrow = MockAnthropicError.httpError(statusCode: 401, message: "Invalid API key")

        let provider = AnthropicProvider(
            apiKey: "sk-ant-invalid",
            textGenModel: "claude-sonnet-4-5-20250929",
            visionModel: "claude-sonnet-4-5-20250929",
            session: mockSession
        )

        do {
            _ = try await provider.extractText(from: Data(), prompt: "test")
            Issue.record("Expected error")
        } catch let error as ProviderError {
            if case .invalidAPIKey = error {} else {
                Issue.record("Expected ProviderError.invalidAPIKey, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Streaming error throws serverError")
    func testStreamingError() async {
        let mockSession = MockAnthropicSession()
        mockSession.streamError = MockAnthropicError.httpError(statusCode: 500, message: "Server error")

        let provider = AnthropicProvider(
            apiKey: "sk-ant-test",
            textGenModel: "claude-sonnet-4-5-20250929",
            visionModel: "claude-sonnet-4-5-20250929",
            session: mockSession
        )

        var caughtError: ProviderError?
        let stream = provider.generate(prompt: "Hi", systemPrompt: "", maxTokens: 100, temperature: 0.7)
        do {
            for try await _ in stream {}
        } catch let error as ProviderError {
            caughtError = error
        } catch {}

        if case .serverError = caughtError {} else {
            Issue.record("Expected ProviderError.serverError, got \(String(describing: caughtError))")
        }
    }

    @Test("Uses x-api-key header not Bearer")
    func testAPIKeyHeaderStyle() {
        let provider = AnthropicProvider(
            apiKey: "sk-ant-test-key",
            textGenModel: "claude-sonnet-4-5-20250929",
            visionModel: "claude-sonnet-4-5-20250929"
        )
        #expect(provider.authHeaderName == "x-api-key")
    }

    // MARK: - Helpers

    private func makeProvider() -> AnthropicProvider {
        AnthropicProvider(
            apiKey: "sk-ant-test",
            textGenModel: "claude-sonnet-4-5-20250929",
            visionModel: "claude-sonnet-4-5-20250929"
        )
    }
}

// MARK: - Mock Types

struct MockAnthropicError: AnthropicHTTPError {
    let statusCode: Int
    let message: String

    static func httpError(statusCode: Int, message: String) -> MockAnthropicError {
        MockAnthropicError(statusCode: statusCode, message: message)
    }
}

final class MockAnthropicSession: AnthropicSessionProtocol, @unchecked Sendable {
    var streamTokens: [String] = []
    var messageResult: String?
    var errorToThrow: Error?
    var streamError: Error?

    var lastModel: String?
    var lastSystemPrompt: String?
    var lastMaxTokens: Int?
    var lastTemperature: Double?
    var lastImageBase64: String?

    func streamMessage(
        model: String,
        messages: [(role: String, content: String, imageBase64: String?)],
        systemPrompt: String?,
        maxTokens: Int,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error> {
        lastModel = model
        lastSystemPrompt = systemPrompt
        lastMaxTokens = maxTokens
        lastTemperature = temperature

        if let msg = messages.first(where: { $0.imageBase64 != nil }) {
            lastImageBase64 = msg.imageBase64
        }

        let tokens = streamTokens
        let error = streamError

        return AsyncThrowingStream { continuation in
            if let error = error {
                let providerError = AnthropicProvider.mapError(error)
                continuation.finish(throwing: providerError)
                return
            }
            for token in tokens {
                continuation.yield(token)
            }
            continuation.finish()
        }
    }

    func createMessage(
        model: String,
        messages: [(role: String, content: String, imageBase64: String?)],
        systemPrompt: String?,
        maxTokens: Int,
        temperature: Double
    ) async throws -> String {
        lastModel = model
        lastSystemPrompt = systemPrompt
        lastMaxTokens = maxTokens
        lastTemperature = temperature

        if let msg = messages.first(where: { $0.imageBase64 != nil }) {
            lastImageBase64 = msg.imageBase64
        }

        if let error = errorToThrow {
            throw AnthropicProvider.mapError(error)
        }

        guard let result = messageResult else {
            throw ProviderError.serverError(500, "No mock result configured")
        }
        return result
    }
}
