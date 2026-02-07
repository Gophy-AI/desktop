import Foundation
import OpenAI

public protocol OpenAISessionProtocol: Sendable {
    func chatStream(
        model: String,
        messages: [(role: String, content: String, imageBase64: String?)],
        maxTokens: Int,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error>

    func chat(
        model: String,
        messages: [(role: String, content: String, imageBase64: String?)],
        maxTokens: Int,
        temperature: Double
    ) async throws -> String

    func embeddings(model: String, input: [String]) async throws -> [[Double]]

    func transcribe(model: String, audioData: Data, fileType: String) async throws -> String
}

public final class OpenAICompatibleProvider: TextGenerationProvider, EmbeddingProvider, STTProvider, VisionProvider, @unchecked Sendable {

    public let providerId: String
    public let dimensions: Int

    private let baseURL: URL
    private let apiKey: String
    private let textGenModel: String?
    private let embeddingModel: String?
    private let sttModel: String?
    private let visionModel: String?
    private let session: OpenAISessionProtocol

    public convenience init(
        providerId: String,
        baseURL: URL,
        apiKey: String,
        textGenModel: String? = nil,
        embeddingModel: String? = nil,
        embeddingDimensions: Int = 1536,
        sttModel: String? = nil,
        visionModel: String? = nil
    ) {
        let session = OpenAILiveSession(baseURL: baseURL, apiKey: apiKey)
        self.init(
            providerId: providerId,
            baseURL: baseURL,
            apiKey: apiKey,
            textGenModel: textGenModel,
            embeddingModel: embeddingModel,
            embeddingDimensions: embeddingDimensions,
            sttModel: sttModel,
            visionModel: visionModel,
            session: session
        )
    }

    public init(
        providerId: String,
        baseURL: URL,
        apiKey: String,
        textGenModel: String? = nil,
        embeddingModel: String? = nil,
        embeddingDimensions: Int = 1536,
        sttModel: String? = nil,
        visionModel: String? = nil,
        session: OpenAISessionProtocol
    ) {
        self.providerId = providerId
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.textGenModel = textGenModel
        self.embeddingModel = embeddingModel
        self.dimensions = embeddingDimensions
        self.sttModel = sttModel
        self.visionModel = visionModel
        self.session = session
    }

    // MARK: - TextGenerationProvider

    public func generate(
        prompt: String,
        systemPrompt: String,
        maxTokens: Int,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error> {
        guard let model = textGenModel else {
            return AsyncThrowingStream { $0.finish(throwing: ProviderError.modelNotAvailable("No text generation model configured")) }
        }

        var messages: [(role: String, content: String, imageBase64: String?)] = []
        if !systemPrompt.isEmpty {
            messages.append((role: "system", content: systemPrompt, imageBase64: nil))
        }
        messages.append((role: "user", content: prompt, imageBase64: nil))

        return session.chatStream(
            model: model,
            messages: messages,
            maxTokens: maxTokens,
            temperature: temperature
        )
    }

    // MARK: - EmbeddingProvider

    public func embed(text: String) async throws -> [Float] {
        guard let model = embeddingModel else {
            throw ProviderError.modelNotAvailable("No embedding model configured")
        }

        let results = try await session.embeddings(model: model, input: [text])
        guard let first = results.first else {
            throw ProviderError.serverError(500, "Empty embedding result")
        }
        return first.map { Float($0) }
    }

    public func embedBatch(texts: [String]) async throws -> [[Float]] {
        guard let model = embeddingModel else {
            throw ProviderError.modelNotAvailable("No embedding model configured")
        }

        let results = try await session.embeddings(model: model, input: texts)
        return results.map { vector in vector.map { Float($0) } }
    }

    // MARK: - STTProvider

    public func transcribe(audioData: Data, format: AudioFormat) async throws -> [TranscriptionSegment] {
        guard let model = sttModel else {
            throw ProviderError.modelNotAvailable("No STT model configured")
        }

        let fileType = format.rawValue
        let text = try await session.transcribe(model: model, audioData: audioData, fileType: fileType)

        return [TranscriptionSegment(text: text, startTime: 0, endTime: 0)]
    }

    // MARK: - VisionProvider

    public func extractText(from imageData: Data, prompt: String) async throws -> String {
        guard let model = visionModel else {
            throw ProviderError.modelNotAvailable("No vision model configured")
        }

        let base64 = imageData.base64EncodedString()
        let messages: [(role: String, content: String, imageBase64: String?)] = [
            (role: "user", content: prompt, imageBase64: base64)
        ]

        return try await session.chat(
            model: model,
            messages: messages,
            maxTokens: 4096,
            temperature: 0.1
        )
    }

    public func analyzeImage(imageData: Data, prompt: String) -> AsyncThrowingStream<String, Error> {
        guard let model = visionModel else {
            return AsyncThrowingStream { $0.finish(throwing: ProviderError.modelNotAvailable("No vision model configured")) }
        }

        let base64 = imageData.base64EncodedString()
        let messages: [(role: String, content: String, imageBase64: String?)] = [
            (role: "user", content: prompt, imageBase64: base64)
        ]

        return session.chatStream(
            model: model,
            messages: messages,
            maxTokens: 4096,
            temperature: 0.3
        )
    }

    // MARK: - Error Mapping

    public static func mapError(_ error: Error) -> ProviderError {
        if let providerError = error as? ProviderError {
            return providerError
        }

        if let httpError = error as? OpenAIHTTPError {
            return mapHTTPError(statusCode: httpError.statusCode, message: httpError.message)
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return .networkError(error.localizedDescription)
        }

        let description = String(describing: error)
        if description.contains("401") || description.lowercased().contains("unauthorized") {
            return .invalidAPIKey
        }
        if description.contains("429") || description.lowercased().contains("rate limit") {
            return .rateLimited(retryAfter: 60)
        }
        if description.contains("500") || description.contains("502") || description.contains("503") {
            return .serverError(500, description)
        }

        return .networkError(error.localizedDescription)
    }

    static func mapHTTPError(statusCode: Int, message: String) -> ProviderError {
        switch statusCode {
        case 401:
            return .invalidAPIKey
        case 429:
            return .rateLimited(retryAfter: 60)
        case 500...599:
            return .serverError(statusCode, message)
        default:
            return .networkError(message)
        }
    }
}

// MARK: - Live OpenAI Session

final class OpenAILiveSession: OpenAISessionProtocol, @unchecked Sendable {
    private let client: OpenAI

    init(baseURL: URL, apiKey: String) {
        let host = baseURL.host ?? "api.openai.com"
        let basePath = baseURL.path.isEmpty ? "/v1" : baseURL.path
        let port = baseURL.port ?? 443
        let scheme = baseURL.scheme ?? "https"

        let configuration = OpenAI.Configuration(
            token: apiKey,
            host: host,
            port: port,
            scheme: scheme,
            basePath: basePath
        )
        self.client = OpenAI(configuration: configuration)
    }

    func chatStream(
        model: String,
        messages: [(role: String, content: String, imageBase64: String?)],
        maxTokens: Int,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error> {
        let chatMessages = messages.compactMap { msg -> ChatQuery.ChatCompletionMessageParam? in
            buildMessage(role: msg.role, content: msg.content, imageBase64: msg.imageBase64)
        }

        let query = ChatQuery(
            messages: chatMessages,
            model: model,
            maxCompletionTokens: maxTokens,
            temperature: temperature
        )

        let sdkStream: AsyncThrowingStream<ChatStreamResult, Error> = client.chatsStream(query: query)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await result in sdkStream {
                        for choice in result.choices {
                            if let content = choice.delta.content {
                                continuation.yield(content)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: OpenAICompatibleProvider.mapError(error))
                }
            }
        }
    }

    func chat(
        model: String,
        messages: [(role: String, content: String, imageBase64: String?)],
        maxTokens: Int,
        temperature: Double
    ) async throws -> String {
        let chatMessages = messages.compactMap { msg -> ChatQuery.ChatCompletionMessageParam? in
            buildMessage(role: msg.role, content: msg.content, imageBase64: msg.imageBase64)
        }

        let query = ChatQuery(
            messages: chatMessages,
            model: model,
            maxCompletionTokens: maxTokens,
            temperature: temperature
        )

        do {
            let result = try await client.chats(query: query)
            guard let choice = result.choices.first else {
                throw ProviderError.serverError(500, "No response choices")
            }
            return choice.message.content ?? ""
        } catch let error as ProviderError {
            throw error
        } catch {
            throw OpenAICompatibleProvider.mapError(error)
        }
    }

    func embeddings(model: String, input: [String]) async throws -> [[Double]] {
        let query = EmbeddingsQuery(
            input: .stringList(input),
            model: model
        )

        do {
            let result = try await client.embeddings(query: query)
            return result.data
                .sorted(by: { $0.index < $1.index })
                .map { $0.embedding }
        } catch let error as ProviderError {
            throw error
        } catch {
            throw OpenAICompatibleProvider.mapError(error)
        }
    }

    func transcribe(model: String, audioData: Data, fileType: String) async throws -> String {
        let audioFileType: AudioTranscriptionQuery.FileType
        switch fileType {
        case "wav": audioFileType = .wav
        case "mp3": audioFileType = .mp3
        case "m4a": audioFileType = .m4a
        case "webm": audioFileType = .webm
        default: audioFileType = .wav
        }

        let query = AudioTranscriptionQuery(
            file: audioData,
            fileType: audioFileType,
            model: model
        )

        do {
            let result = try await client.audioTranscriptions(query: query)
            return result.text
        } catch let error as ProviderError {
            throw error
        } catch {
            throw OpenAICompatibleProvider.mapError(error)
        }
    }

    private func buildMessage(role: String, content: String, imageBase64: String?) -> ChatQuery.ChatCompletionMessageParam? {
        if let imageBase64 = imageBase64 {
            let parts: [ChatQuery.ChatCompletionMessageParam.UserMessageParam.Content.ContentPart] = [
                .text(ChatQuery.ChatCompletionMessageParam.ContentPartTextParam(text: content)),
                .image(ChatQuery.ChatCompletionMessageParam.ContentPartImageParam(
                    imageUrl: .init(url: "data:image/jpeg;base64,\(imageBase64)", detail: .auto)
                ))
            ]
            return .user(.init(content: .contentParts(parts)))
        }

        return ChatQuery.ChatCompletionMessageParam(role: role == "system" ? .system : .user, content: content)
    }
}
