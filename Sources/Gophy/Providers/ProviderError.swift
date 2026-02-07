import Foundation

public enum ProviderError: Error, Sendable {
    case notConfigured
    case invalidAPIKey
    case rateLimited(retryAfter: TimeInterval)
    case modelNotAvailable(String)
    case networkError(String)
    case serverError(Int, String)
    case streamingError(String)
}

public protocol OpenAIHTTPError: Error {
    var statusCode: Int { get }
    var message: String { get }
}

public protocol AnthropicHTTPError: Error {
    var statusCode: Int { get }
    var message: String { get }
}
