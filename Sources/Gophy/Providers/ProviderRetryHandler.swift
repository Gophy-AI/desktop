import Foundation
import os.log

private let retryLogger = Logger(subsystem: "com.gophy.app", category: "ProviderRetryHandler")

public struct RetryConfiguration: Sendable {
    public let maxAttempts: Int
    public let initialBackoff: TimeInterval
    public let maxBackoff: TimeInterval
    public let backoffMultiplier: Double

    public init(
        maxAttempts: Int = 3,
        initialBackoff: TimeInterval = 1.0,
        maxBackoff: TimeInterval = 16.0,
        backoffMultiplier: Double = 2.0
    ) {
        self.maxAttempts = maxAttempts
        self.initialBackoff = initialBackoff
        self.maxBackoff = maxBackoff
        self.backoffMultiplier = backoffMultiplier
    }

    public static let `default` = RetryConfiguration()
}

public enum ProviderRetryHandler {

    public static func withRetry<T: Sendable>(
        configuration: RetryConfiguration = .default,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        var currentBackoff = configuration.initialBackoff

        for attempt in 1...configuration.maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error

                let mapped = mapForRetry(error)
                switch mapped {
                case .doNotRetry:
                    retryLogger.warning("Non-retryable error on attempt \(attempt): \(error.localizedDescription, privacy: .public)")
                    throw error

                case .retryAfter(let delay):
                    guard attempt < configuration.maxAttempts else { break }
                    retryLogger.info("Rate limited, retrying after \(delay)s (attempt \(attempt)/\(configuration.maxAttempts))")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                case .retryWithBackoff:
                    guard attempt < configuration.maxAttempts else { break }
                    let delay = min(currentBackoff, configuration.maxBackoff)
                    retryLogger.info("Retryable error, backing off \(delay)s (attempt \(attempt)/\(configuration.maxAttempts))")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    currentBackoff *= configuration.backoffMultiplier
                }
            }
        }

        throw lastError ?? ProviderError.networkError("Max retry attempts exceeded")
    }

    public static func withStreamRetry(
        configuration: RetryConfiguration = .default,
        operation: @Sendable @escaping () -> AsyncThrowingStream<String, Error>
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var lastError: Error?
                var currentBackoff = configuration.initialBackoff

                for attempt in 1...configuration.maxAttempts {
                    var receivedAnyData = false

                    do {
                        let stream = operation()
                        for try await chunk in stream {
                            receivedAnyData = true
                            continuation.yield(chunk)
                        }
                        continuation.finish()
                        return
                    } catch {
                        lastError = error

                        let mapped = mapForRetry(error)
                        switch mapped {
                        case .doNotRetry:
                            retryLogger.warning("Non-retryable stream error on attempt \(attempt): \(error.localizedDescription, privacy: .public)")
                            continuation.finish(throwing: error)
                            return

                        case .retryAfter(let delay):
                            guard attempt < configuration.maxAttempts else { break }
                            if receivedAnyData {
                                retryLogger.info("Partial stream received before rate limit, retrying after \(delay)s")
                            }
                            do {
                                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                            } catch {
                                continuation.finish(throwing: error)
                                return
                            }

                        case .retryWithBackoff:
                            guard attempt < configuration.maxAttempts else { break }
                            let delay = min(currentBackoff, configuration.maxBackoff)
                            retryLogger.info("Retryable stream error, backing off \(delay)s (attempt \(attempt)/\(configuration.maxAttempts))")
                            do {
                                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                            } catch {
                                continuation.finish(throwing: error)
                                return
                            }
                            currentBackoff *= configuration.backoffMultiplier
                        }
                    }
                }

                continuation.finish(throwing: lastError ?? ProviderError.networkError("Max retry attempts exceeded"))
            }
        }
    }

    // MARK: - Classification

    private enum RetryDecision {
        case doNotRetry
        case retryAfter(TimeInterval)
        case retryWithBackoff
    }

    private static func mapForRetry(_ error: Error) -> RetryDecision {
        if let providerError = error as? ProviderError {
            switch providerError {
            case .invalidAPIKey:
                return .doNotRetry
            case .modelNotAvailable:
                return .doNotRetry
            case .notConfigured:
                return .doNotRetry
            case .rateLimited(let retryAfter):
                return .retryAfter(retryAfter)
            case .serverError(let code, _):
                if code >= 500 && code <= 599 {
                    return .retryWithBackoff
                }
                return .doNotRetry
            case .networkError:
                return .retryWithBackoff
            case .streamingError:
                return .retryWithBackoff
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorNotConnectedToInternet:
                return .retryWithBackoff
            default:
                return .retryWithBackoff
            }
        }

        return .doNotRetry
    }
}
