import Foundation
import SwiftAnthropic

public protocol AnthropicSessionProtocol: Sendable {
    func streamMessage(
        model: String,
        messages: [(role: String, content: String, imageBase64: String?)],
        systemPrompt: String?,
        maxTokens: Int,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error>

    func createMessage(
        model: String,
        messages: [(role: String, content: String, imageBase64: String?)],
        systemPrompt: String?,
        maxTokens: Int,
        temperature: Double
    ) async throws -> String
}

public final class AnthropicProvider: TextGenerationProvider, VisionProvider, @unchecked Sendable {

    public let authHeaderName = "x-api-key"

    private let apiKey: String
    private let textGenModel: String
    private let visionModel: String
    private let session: AnthropicSessionProtocol

    public convenience init(
        apiKey: String,
        textGenModel: String = "claude-sonnet-4-5-20250929",
        visionModel: String = "claude-sonnet-4-5-20250929"
    ) {
        let session = AnthropicLiveSession(apiKey: apiKey)
        self.init(
            apiKey: apiKey,
            textGenModel: textGenModel,
            visionModel: visionModel,
            session: session
        )
    }

    public init(
        apiKey: String,
        textGenModel: String = "claude-sonnet-4-5-20250929",
        visionModel: String = "claude-sonnet-4-5-20250929",
        session: AnthropicSessionProtocol
    ) {
        self.apiKey = apiKey
        self.textGenModel = textGenModel
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
        let system = systemPrompt.isEmpty ? nil : systemPrompt
        let messages: [(role: String, content: String, imageBase64: String?)] = [
            (role: "user", content: prompt, imageBase64: nil)
        ]

        return session.streamMessage(
            model: textGenModel,
            messages: messages,
            systemPrompt: system,
            maxTokens: maxTokens,
            temperature: temperature
        )
    }

    // MARK: - VisionProvider

    public func extractText(from imageData: Data, prompt: String) async throws -> String {
        let base64 = imageData.base64EncodedString()
        let messages: [(role: String, content: String, imageBase64: String?)] = [
            (role: "user", content: prompt, imageBase64: base64)
        ]

        return try await session.createMessage(
            model: visionModel,
            messages: messages,
            systemPrompt: nil,
            maxTokens: 4096,
            temperature: 0.1
        )
    }

    public func analyzeImage(imageData: Data, prompt: String) -> AsyncThrowingStream<String, Error> {
        let base64 = imageData.base64EncodedString()
        let messages: [(role: String, content: String, imageBase64: String?)] = [
            (role: "user", content: prompt, imageBase64: base64)
        ]

        return session.streamMessage(
            model: visionModel,
            messages: messages,
            systemPrompt: nil,
            maxTokens: 4096,
            temperature: 0.3
        )
    }

    // MARK: - Error Mapping

    public static func mapError(_ error: Error) -> ProviderError {
        if let providerError = error as? ProviderError {
            return providerError
        }

        if let httpError = error as? AnthropicHTTPError {
            return mapHTTPError(statusCode: httpError.statusCode, message: httpError.message)
        }

        let description = String(describing: error)
        if description.contains("401") || description.lowercased().contains("unauthorized") || (description.lowercased().contains("invalid") && description.lowercased().contains("key")) {
            return .invalidAPIKey
        }
        if description.contains("429") || description.lowercased().contains("rate limit") {
            return .rateLimited(retryAfter: 60)
        }
        if description.contains("status code 5") || description.contains("500") || description.contains("502") || description.contains("503") {
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

// MARK: - HealthCheckable

extension AnthropicProvider: HealthCheckable {
    public func healthCheck() async -> ProviderHealthStatus {
        do {
            let result = try await session.createMessage(
                model: textGenModel,
                messages: [(role: "user", content: "ping", imageBase64: nil)],
                systemPrompt: nil,
                maxTokens: 1,
                temperature: 0
            )
            _ = result
            return .healthy
        } catch {
            let mapped = Self.mapError(error)
            switch mapped {
            case .invalidAPIKey:
                return .unavailable("Invalid API key")
            case .rateLimited:
                return .degraded("Rate limited")
            case .serverError(let code, let msg):
                return .unavailable("Server error \(code): \(msg)")
            case .networkError(let msg):
                return .unavailable("Network error: \(msg)")
            default:
                return .unavailable(error.localizedDescription)
            }
        }
    }
}

// MARK: - Live Anthropic Session

final class AnthropicLiveSession: AnthropicSessionProtocol, @unchecked Sendable {
    private let service: AnthropicService

    init(apiKey: String) {
        self.service = AnthropicServiceFactory.service(
            apiKey: apiKey,
            betaHeaders: nil
        )
    }

    func streamMessage(
        model: String,
        messages: [(role: String, content: String, imageBase64: String?)],
        systemPrompt: String?,
        maxTokens: Int,
        temperature: Double
    ) -> AsyncThrowingStream<String, Error> {
        let anthropicMessages = buildMessages(messages)
        let system: MessageParameter.System? = systemPrompt.map { .text($0) }

        let parameter = MessageParameter(
            model: .other(model),
            messages: anthropicMessages,
            maxTokens: maxTokens,
            system: system,
            stream: true,
            temperature: temperature
        )

        let box = SendableBox((parameter, service))
        return AsyncThrowingStream { continuation in
            Task { @Sendable in
                let (param, svc) = box.value
                do {
                    let stream = try await svc.streamMessage(param)
                    for try await response in stream {
                        if let delta = response.delta, let text = delta.text {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AnthropicProvider.mapError(error))
                }
            }
        }
    }

    func createMessage(
        model: String,
        messages: [(role: String, content: String, imageBase64: String?)],
        systemPrompt: String?,
        maxTokens: Int,
        temperature: Double
    ) async throws -> String {
        let anthropicMessages = buildMessages(messages)
        let system: MessageParameter.System? = systemPrompt.map { .text($0) }

        let parameter = MessageParameter(
            model: .other(model),
            messages: anthropicMessages,
            maxTokens: maxTokens,
            system: system,
            stream: false,
            temperature: temperature
        )

        do {
            let response = try await service.createMessage(parameter)
            let textContent = response.content.compactMap { block -> String? in
                switch block {
                case .text(let text):
                    return text
                case .toolUse:
                    return nil
                }
            }
            return textContent.joined()
        } catch let error as ProviderError {
            throw error
        } catch {
            throw AnthropicProvider.mapError(error)
        }
    }

    private func buildMessages(_ messages: [(role: String, content: String, imageBase64: String?)]) -> [MessageParameter.Message] {
        messages.map { msg in
            let role: MessageParameter.Message.Role = msg.role == "assistant" ? .assistant : .user

            if let imageBase64 = msg.imageBase64 {
                let imageSource = MessageParameter.Message.Content.ImageSource(
                    type: .base64,
                    mediaType: .jpeg,
                    data: imageBase64
                )
                return MessageParameter.Message(
                    role: role,
                    content: .list([
                        .image(imageSource),
                        .text(msg.content)
                    ])
                )
            }

            return MessageParameter.Message(role: role, content: .text(msg.content))
        }
    }
}

// MARK: - Sendable Wrapper

private struct SendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
