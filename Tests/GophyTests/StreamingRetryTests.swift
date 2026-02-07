import Testing
import Foundation
@testable import Gophy

// MARK: - Test Helpers

private actor CallCounter {
    var count = 0

    func increment() -> Int {
        count += 1
        return count
    }
}

@Suite("ProviderRetryHandler Tests")
struct StreamingRetryTests {

    // MARK: - withRetry Tests

    @Test("withRetry succeeds on first attempt")
    func testRetrySucceedsFirstAttempt() async throws {
        let counter = CallCounter()
        let config = RetryConfiguration(maxAttempts: 3, initialBackoff: 0.01)

        let result = try await ProviderRetryHandler.withRetry(configuration: config) {
            _ = await counter.increment()
            return "success"
        }

        #expect(result == "success")
        #expect(await counter.count == 1)
    }

    @Test("withRetry does not retry on 401 invalidAPIKey")
    func testRetryDoesNotRetryOn401() async throws {
        let counter = CallCounter()
        let config = RetryConfiguration(maxAttempts: 3, initialBackoff: 0.01)

        do {
            let _: String = try await ProviderRetryHandler.withRetry(configuration: config) {
                _ = await counter.increment()
                throw ProviderError.invalidAPIKey
            }
            Issue.record("Should have thrown")
        } catch {
            #expect(error is ProviderError)
            if case .invalidAPIKey = error as? ProviderError {} else {
                Issue.record("Expected invalidAPIKey, got \(error)")
            }
        }

        #expect(await counter.count == 1)
    }

    @Test("withRetry retries on 429 rate limited")
    func testRetryRetriesOn429() async throws {
        let counter = CallCounter()
        let config = RetryConfiguration(maxAttempts: 3, initialBackoff: 0.01)

        let result = try await ProviderRetryHandler.withRetry(configuration: config) {
            let attempt = await counter.increment()
            if attempt < 2 {
                throw ProviderError.rateLimited(retryAfter: 0.01)
            }
            return "recovered"
        }

        #expect(result == "recovered")
        #expect(await counter.count == 2)
    }

    @Test("withRetry retries on 500 server error with backoff")
    func testRetryRetriesOn500() async throws {
        let counter = CallCounter()
        let config = RetryConfiguration(maxAttempts: 3, initialBackoff: 0.01)

        let result = try await ProviderRetryHandler.withRetry(configuration: config) {
            let attempt = await counter.increment()
            if attempt < 3 {
                throw ProviderError.serverError(500, "Internal Server Error")
            }
            return "recovered"
        }

        #expect(result == "recovered")
        #expect(await counter.count == 3)
    }

    @Test("withRetry exhausts max attempts then throws")
    func testRetryExhaustsAttempts() async throws {
        let counter = CallCounter()
        let config = RetryConfiguration(maxAttempts: 2, initialBackoff: 0.01)

        do {
            let _: String = try await ProviderRetryHandler.withRetry(configuration: config) {
                _ = await counter.increment()
                throw ProviderError.serverError(503, "Service Unavailable")
            }
            Issue.record("Should have thrown")
        } catch {
            #expect(error is ProviderError)
        }

        #expect(await counter.count == 2)
    }

    @Test("withRetry retries on network timeout")
    func testRetryRetriesOnNetworkTimeout() async throws {
        let counter = CallCounter()
        let config = RetryConfiguration(maxAttempts: 3, initialBackoff: 0.01)

        let result = try await ProviderRetryHandler.withRetry(configuration: config) {
            let attempt = await counter.increment()
            if attempt < 2 {
                throw NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
            }
            return "recovered"
        }

        #expect(result == "recovered")
        #expect(await counter.count == 2)
    }

    @Test("withRetry does not retry on modelNotAvailable")
    func testRetryDoesNotRetryOnModelNotAvailable() async throws {
        let counter = CallCounter()
        let config = RetryConfiguration(maxAttempts: 3, initialBackoff: 0.01)

        do {
            let _: String = try await ProviderRetryHandler.withRetry(configuration: config) {
                _ = await counter.increment()
                throw ProviderError.modelNotAvailable("No model")
            }
            Issue.record("Should have thrown")
        } catch {
            #expect(error is ProviderError)
        }

        #expect(await counter.count == 1)
    }

    // MARK: - withStreamRetry Tests

    @Test("withStreamRetry succeeds on first attempt")
    func testStreamRetrySucceedsFirstAttempt() async throws {
        let config = RetryConfiguration(maxAttempts: 3, initialBackoff: 0.01)

        let stream = ProviderRetryHandler.withStreamRetry(configuration: config) {
            AsyncThrowingStream { continuation in
                continuation.yield("hello ")
                continuation.yield("world")
                continuation.finish()
            }
        }

        var collected = ""
        for try await chunk in stream {
            collected += chunk
        }

        #expect(collected == "hello world")
    }

    @Test("withStreamRetry does not retry on 401")
    func testStreamRetryDoesNotRetryOn401() async throws {
        let counter = CallCounter()
        let config = RetryConfiguration(maxAttempts: 3, initialBackoff: 0.01)

        let stream = ProviderRetryHandler.withStreamRetry(configuration: config) {
            AsyncThrowingStream<String, Error> { continuation in
                Task {
                    _ = await counter.increment()
                    continuation.finish(throwing: ProviderError.invalidAPIKey)
                }
            }
        }

        do {
            for try await _ in stream {}
            Issue.record("Should have thrown")
        } catch {
            #expect(error is ProviderError)
            if case .invalidAPIKey = error as? ProviderError {} else {
                Issue.record("Expected invalidAPIKey, got \(error)")
            }
        }

        // Allow time for counter to settle
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(await counter.count == 1)
    }

    @Test("withStreamRetry retries on server error")
    func testStreamRetryRetriesOnServerError() async throws {
        let counter = CallCounter()
        let config = RetryConfiguration(maxAttempts: 3, initialBackoff: 0.01)

        let stream = ProviderRetryHandler.withStreamRetry(configuration: config) {
            AsyncThrowingStream { continuation in
                Task {
                    let attempt = await counter.increment()
                    if attempt < 2 {
                        continuation.finish(throwing: ProviderError.serverError(500, "ISE"))
                    } else {
                        continuation.yield("success")
                        continuation.finish()
                    }
                }
            }
        }

        var collected = ""
        for try await chunk in stream {
            collected += chunk
        }

        #expect(collected == "success")
        #expect(await counter.count == 2)
    }

    @Test("withStreamRetry handles partial stream then error with retry")
    func testStreamRetryPartialStreamThenError() async throws {
        let counter = CallCounter()
        let config = RetryConfiguration(maxAttempts: 3, initialBackoff: 0.01)

        let stream = ProviderRetryHandler.withStreamRetry(configuration: config) {
            AsyncThrowingStream { continuation in
                Task {
                    let attempt = await counter.increment()
                    if attempt < 2 {
                        continuation.yield("partial")
                        continuation.finish(throwing: ProviderError.streamingError("connection reset"))
                    } else {
                        continuation.yield("full response")
                        continuation.finish()
                    }
                }
            }
        }

        var chunks: [String] = []
        for try await chunk in stream {
            chunks.append(chunk)
        }

        #expect(chunks.contains("partial"))
        #expect(chunks.contains("full response"))
        #expect(await counter.count == 2)
    }

    @Test("withStreamRetry cancellation stops retries")
    func testStreamRetryCancellation() async throws {
        let counter = CallCounter()
        let config = RetryConfiguration(maxAttempts: 5, initialBackoff: 0.5)

        let stream = ProviderRetryHandler.withStreamRetry(configuration: config) {
            AsyncThrowingStream<String, Error> { continuation in
                Task {
                    _ = await counter.increment()
                    continuation.finish(throwing: ProviderError.networkError("timeout"))
                }
            }
        }

        let task = Task {
            for try await _ in stream {}
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        // Allow time for cancellation to propagate
        try await Task.sleep(nanoseconds: 100_000_000)

        let count = await counter.count
        #expect(count < 5)
    }
}
