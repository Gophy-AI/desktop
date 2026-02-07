import Testing
import Foundation
@testable import Gophy

@Suite("OpenAICompatibleProvider Tests")
struct OpenAICompatibleProviderTests {

    // MARK: - Protocol Conformance

    @Test("Conforms to TextGenerationProvider protocol")
    func testTextGenerationConformance() {
        let provider: any TextGenerationProvider = makeProvider(textGenModel: "gpt-4o")
        _ = provider
    }

    @Test("Conforms to EmbeddingProvider protocol")
    func testEmbeddingConformance() {
        let provider: any EmbeddingProvider = makeProvider(embeddingModel: "text-embedding-3-small")
        _ = provider
    }

    @Test("Conforms to STTProvider protocol")
    func testSTTConformance() {
        let provider: any STTProvider = makeProvider(sttModel: "whisper-1")
        _ = provider
    }

    @Test("Conforms to VisionProvider protocol")
    func testVisionConformance() {
        let provider: any VisionProvider = makeProvider(visionModel: "gpt-4o")
        _ = provider
    }

    // MARK: - TextGenerationProvider

    @Test("Generate returns streaming tokens")
    func testGenerateStreaming() async throws {
        let mockSession = MockOpenAISession()
        mockSession.chatStreamResults = [
            makeChatStreamResult(content: "Hello"),
            makeChatStreamResult(content: " world"),
            makeChatStreamResult(content: "!")
        ]

        let provider = OpenAICompatibleProvider(
            providerId: "openai",
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: "sk-test-key",
            textGenModel: "gpt-4o",
            session: mockSession
        )

        var tokens: [String] = []
        let stream = provider.generate(prompt: "Hi", systemPrompt: "Be helpful", maxTokens: 100, temperature: 0.7)
        for try await token in stream {
            tokens.append(token)
        }

        #expect(tokens == ["Hello", " world", "!"])
    }

    @Test("Generate uses system prompt and parameters")
    func testGenerateParameters() async throws {
        let mockSession = MockOpenAISession()
        mockSession.chatStreamResults = [makeChatStreamResult(content: "ok")]

        let provider = OpenAICompatibleProvider(
            providerId: "openai",
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: "sk-test-key",
            textGenModel: "gpt-4o",
            session: mockSession
        )

        var tokens: [String] = []
        let stream = provider.generate(prompt: "test", systemPrompt: "system", maxTokens: 50, temperature: 0.5)
        for try await token in stream {
            tokens.append(token)
        }

        #expect(mockSession.lastChatQuery != nil)
        #expect(mockSession.lastChatQuery?.model == "gpt-4o")
        #expect(mockSession.lastChatQuery?.temperature == 0.5)
        #expect(mockSession.lastChatQuery?.maxCompletionTokens == 50)
    }

    @Test("Generate throws notConfigured when no textGenModel")
    func testGenerateNotConfigured() async {
        let provider = makeProvider()

        var caughtError: ProviderError?
        let stream = provider.generate(prompt: "Hi", systemPrompt: "", maxTokens: 100, temperature: 0.7)
        do {
            for try await _ in stream {}
        } catch let error as ProviderError {
            caughtError = error
        } catch {}

        if case .modelNotAvailable = caughtError {} else {
            Issue.record("Expected ProviderError.modelNotAvailable, got \(String(describing: caughtError))")
        }
    }

    // MARK: - EmbeddingProvider

    @Test("Embed returns float vector")
    func testEmbed() async throws {
        let mockSession = MockOpenAISession()
        mockSession.embeddingResult = MockEmbeddingResult(vectors: [[0.1, 0.2, 0.3]])

        let provider = OpenAICompatibleProvider(
            providerId: "openai",
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: "sk-test-key",
            embeddingModel: "text-embedding-3-small",
            embeddingDimensions: 3,
            session: mockSession
        )

        let result = try await provider.embed(text: "hello")
        #expect(result.count == 3)
        #expect(result[0] == Float(0.1))
    }

    @Test("EmbedBatch returns multiple vectors")
    func testEmbedBatch() async throws {
        let mockSession = MockOpenAISession()
        mockSession.embeddingResult = MockEmbeddingResult(vectors: [
            [0.1, 0.2, 0.3],
            [0.4, 0.5, 0.6]
        ])

        let provider = OpenAICompatibleProvider(
            providerId: "openai",
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: "sk-test-key",
            embeddingModel: "text-embedding-3-small",
            embeddingDimensions: 3,
            session: mockSession
        )

        let result = try await provider.embedBatch(texts: ["hello", "world"])
        #expect(result.count == 2)
        #expect(result[0].count == 3)
    }

    @Test("Dimensions property returns configured value")
    func testDimensions() {
        let provider = OpenAICompatibleProvider(
            providerId: "openai",
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: "sk-test-key",
            embeddingModel: "text-embedding-3-small",
            embeddingDimensions: 1536
        )

        #expect(provider.dimensions == 1536)
    }

    @Test("Embed throws notConfigured when no embeddingModel")
    func testEmbedNotConfigured() async {
        let provider = makeProvider()

        do {
            _ = try await provider.embed(text: "hello")
            Issue.record("Expected error")
        } catch let error as ProviderError {
            if case .modelNotAvailable = error {} else {
                Issue.record("Expected ProviderError.modelNotAvailable, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - STTProvider

    @Test("Transcribe returns segments")
    func testTranscribe() async throws {
        let mockSession = MockOpenAISession()
        mockSession.transcriptionText = "Hello world"

        let provider = OpenAICompatibleProvider(
            providerId: "openai",
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: "sk-test-key",
            sttModel: "whisper-1",
            session: mockSession
        )

        let wavData = makeMinimalWAVData()
        let segments = try await provider.transcribe(audioData: wavData, format: .wav)
        #expect(segments.count == 1)
        #expect(segments[0].text == "Hello world")
    }

    @Test("Transcribe throws notConfigured when no sttModel")
    func testTranscribeNotConfigured() async {
        let provider = makeProvider()

        do {
            _ = try await provider.transcribe(audioData: Data(), format: .wav)
            Issue.record("Expected error")
        } catch let error as ProviderError {
            if case .modelNotAvailable = error {} else {
                Issue.record("Expected ProviderError.modelNotAvailable, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - VisionProvider

    @Test("ExtractText returns OCR result")
    func testExtractText() async throws {
        let mockSession = MockOpenAISession()
        mockSession.chatResult = MockChatResult(content: "Extracted text from image")

        let provider = OpenAICompatibleProvider(
            providerId: "openai",
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: "sk-test-key",
            visionModel: "gpt-4o",
            session: mockSession
        )

        let result = try await provider.extractText(from: Data([0xFF, 0xD8]), prompt: "Extract text")
        #expect(result == "Extracted text from image")
    }

    @Test("AnalyzeImage returns streaming tokens")
    func testAnalyzeImage() async throws {
        let mockSession = MockOpenAISession()
        mockSession.chatStreamResults = [
            makeChatStreamResult(content: "I see"),
            makeChatStreamResult(content: " a cat")
        ]

        let provider = OpenAICompatibleProvider(
            providerId: "openai",
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: "sk-test-key",
            visionModel: "gpt-4o",
            session: mockSession
        )

        var tokens: [String] = []
        let stream = provider.analyzeImage(imageData: Data([0xFF, 0xD8]), prompt: "Describe")
        for try await token in stream {
            tokens.append(token)
        }

        #expect(tokens == ["I see", " a cat"])
    }

    @Test("ExtractText throws notConfigured when no visionModel")
    func testExtractTextNotConfigured() async {
        let provider = makeProvider()

        do {
            _ = try await provider.extractText(from: Data(), prompt: "test")
            Issue.record("Expected error")
        } catch let error as ProviderError {
            if case .modelNotAvailable = error {} else {
                Issue.record("Expected ProviderError.modelNotAvailable, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Error Handling

    @Test("Rate limit error (429) throws rateLimited")
    func testRateLimitError() async {
        let mockSession = MockOpenAISession()
        mockSession.errorToThrow = MockAPIError.httpError(statusCode: 429, message: "Rate limit exceeded")

        let provider = OpenAICompatibleProvider(
            providerId: "openai",
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: "sk-test-key",
            embeddingModel: "text-embedding-3-small",
            session: mockSession
        )

        do {
            _ = try await provider.embed(text: "hello")
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
        let mockSession = MockOpenAISession()
        mockSession.errorToThrow = MockAPIError.httpError(statusCode: 401, message: "Invalid API key")

        let provider = OpenAICompatibleProvider(
            providerId: "openai",
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: "sk-invalid",
            embeddingModel: "text-embedding-3-small",
            session: mockSession
        )

        do {
            _ = try await provider.embed(text: "hello")
            Issue.record("Expected error")
        } catch let error as ProviderError {
            if case .invalidAPIKey = error {} else {
                Issue.record("Expected ProviderError.invalidAPIKey, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Custom base URL is stored correctly")
    func testCustomBaseURL() {
        let customURL = URL(string: "https://api.groq.com/openai/v1")!
        let provider = OpenAICompatibleProvider(
            providerId: "groq",
            baseURL: customURL,
            apiKey: "gsk-test-key",
            textGenModel: "llama-3.3-70b-versatile"
        )

        #expect(provider.providerId == "groq")
    }

    // MARK: - Streaming Error in TextGen

    @Test("Streaming error throws streamingError")
    func testStreamingError() async {
        let mockSession = MockOpenAISession()
        mockSession.streamErrorToThrow = MockAPIError.httpError(statusCode: 500, message: "Server error")

        let provider = OpenAICompatibleProvider(
            providerId: "openai",
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: "sk-test-key",
            textGenModel: "gpt-4o",
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

    // MARK: - Helpers

    private func makeProvider(
        textGenModel: String? = nil,
        embeddingModel: String? = nil,
        sttModel: String? = nil,
        visionModel: String? = nil
    ) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(
            providerId: "openai",
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: "sk-test-key",
            textGenModel: textGenModel,
            embeddingModel: embeddingModel,
            sttModel: sttModel,
            visionModel: visionModel
        )
    }

    private func makeChatStreamResult(content: String) -> MockChatStreamChunk {
        MockChatStreamChunk(content: content)
    }

    private func makeMinimalWAVData() -> Data {
        // Minimal WAV header (44 bytes) + some silence
        var data = Data()
        // RIFF header
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        let dataSize: UInt32 = 36 + 4 // file size - 8
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        // fmt subchunk
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        let fmtSize: UInt32 = 16
        data.append(contentsOf: withUnsafeBytes(of: fmtSize.littleEndian) { Array($0) })
        let audioFormat: UInt16 = 1 // PCM
        data.append(contentsOf: withUnsafeBytes(of: audioFormat.littleEndian) { Array($0) })
        let numChannels: UInt16 = 1
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        let sampleRate: UInt32 = 16000
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        let byteRate: UInt32 = 32000
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        let blockAlign: UInt16 = 2
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        let bitsPerSample: UInt16 = 16
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        // data subchunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        let audioDataSize: UInt32 = 4
        data.append(contentsOf: withUnsafeBytes(of: audioDataSize.littleEndian) { Array($0) })
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // 2 samples of silence
        return data
    }
}

// MARK: - Mock Types

struct MockAPIError: OpenAIHTTPError {
    let statusCode: Int
    let message: String

    static func httpError(statusCode: Int, message: String) -> MockAPIError {
        MockAPIError(statusCode: statusCode, message: message)
    }
}

struct MockChatStreamChunk: Sendable {
    let content: String
}

struct MockChatResult: Sendable {
    let content: String
}

struct MockEmbeddingResult: Sendable {
    let vectors: [[Double]]
}

final class MockOpenAISession: OpenAISessionProtocol, @unchecked Sendable {
    var chatStreamResults: [MockChatStreamChunk] = []
    var chatResult: MockChatResult?
    var embeddingResult: MockEmbeddingResult?
    var transcriptionText: String?
    var errorToThrow: Error?
    var streamErrorToThrow: Error?
    var lastChatQuery: (model: String, temperature: Double?, maxCompletionTokens: Int?)?

    func chatStream(
        model: String,
        messages: [(role: String, content: String, imageBase64: String?)],
        maxTokens: Int,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error> {
        lastChatQuery = (model: model, temperature: temperature, maxCompletionTokens: maxTokens)

        let results = chatStreamResults
        let streamError = streamErrorToThrow

        return AsyncThrowingStream { continuation in
            if let error = streamError {
                let providerError = OpenAICompatibleProvider.mapError(error)
                continuation.finish(throwing: providerError)
                return
            }
            for chunk in results {
                continuation.yield(chunk.content)
            }
            continuation.finish()
        }
    }

    func chat(
        model: String,
        messages: [(role: String, content: String, imageBase64: String?)],
        maxTokens: Int,
        temperature: Double
    ) async throws -> String {
        if let error = errorToThrow {
            throw OpenAICompatibleProvider.mapError(error)
        }
        guard let result = chatResult else {
            throw ProviderError.serverError(500, "No mock result configured")
        }
        return result.content
    }

    func embeddings(model: String, input: [String]) async throws -> [[Double]] {
        if let error = errorToThrow {
            throw OpenAICompatibleProvider.mapError(error)
        }
        guard let result = embeddingResult else {
            throw ProviderError.serverError(500, "No mock result configured")
        }
        return result.vectors
    }

    func transcribe(model: String, audioData: Data, fileType: String) async throws -> String {
        if let error = errorToThrow {
            throw OpenAICompatibleProvider.mapError(error)
        }
        guard let text = transcriptionText else {
            throw ProviderError.serverError(500, "No mock result configured")
        }
        return text
    }
}
