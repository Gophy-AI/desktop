import XCTest
@testable import Gophy

final class GoogleAuthServiceTests: XCTestCase {

    // MARK: - Mock Auth Session Store

    actor MockAuthSessionStore {
        private var storedData: Data?
        private(set) var saveCallCount = 0
        private(set) var removeCallCount = 0

        func save(_ data: Data) {
            storedData = data
            saveCallCount += 1
        }

        func retrieve() -> Data? {
            storedData
        }

        func remove() {
            storedData = nil
            removeCallCount += 1
        }
    }

    // MARK: - Mock OAuth Provider

    actor MockOAuthProvider: OAuthProviderProtocol {
        var shouldSucceed = true
        var shouldCancel = false
        private(set) var signInCallCount = 0
        var tokenToReturn = OAuthTokens(
            accessToken: "mock-access-token",
            refreshToken: "mock-refresh-token",
            expiresAt: Date().addingTimeInterval(3600),
            idToken: nil,
            userEmail: "test@example.com"
        )
        var expiredTokenToReturn: OAuthTokens?
        var refreshedToken = OAuthTokens(
            accessToken: "refreshed-access-token",
            refreshToken: "mock-refresh-token",
            expiresAt: Date().addingTimeInterval(3600),
            idToken: nil,
            userEmail: "test@example.com"
        )
        private(set) var refreshCallCount = 0

        func setResult(shouldSucceed: Bool, shouldCancel: Bool = false) {
            self.shouldSucceed = shouldSucceed
            self.shouldCancel = shouldCancel
        }

        nonisolated func signIn(
            config: GoogleCalendarConfig,
            presentingWindow: sending AnyObject?
        ) async throws -> OAuthTokens {
            await incrementSignInCount()
            let cancel = await self.shouldCancel
            if cancel {
                throw GoogleAuthError.userCancelled
            }
            let succeed = await self.shouldSucceed
            guard succeed else {
                throw GoogleAuthError.authorizationFailed("Mock failure")
            }
            return await self.tokenToReturn
        }

        nonisolated func refreshAccessToken(
            refreshToken: String,
            config: GoogleCalendarConfig
        ) async throws -> OAuthTokens {
            await incrementRefreshCount()
            return await self.refreshedToken
        }

        private func incrementSignInCount() {
            signInCallCount += 1
        }

        private func incrementRefreshCount() {
            refreshCallCount += 1
        }
    }

    // MARK: - Mock Token Store

    final class MockTokenStore: TokenStoreProtocol, @unchecked Sendable {
        private let lock = NSLock()
        private var storedTokens: OAuthTokens?
        private(set) var saveCallCount = 0
        private(set) var removeCallCount = 0

        func save(_ tokens: OAuthTokens) throws {
            lock.lock()
            defer { lock.unlock() }
            storedTokens = tokens
            saveCallCount += 1
        }

        func retrieve() throws -> OAuthTokens? {
            lock.lock()
            defer { lock.unlock() }
            return storedTokens
        }

        func remove() throws {
            lock.lock()
            defer { lock.unlock() }
            storedTokens = nil
            removeCallCount += 1
        }

        func setTokens(_ tokens: OAuthTokens?) {
            lock.lock()
            defer { lock.unlock() }
            storedTokens = tokens
        }
    }

    // MARK: - Tests

    private var config: GoogleCalendarConfig!
    private var mockOAuthProvider: MockOAuthProvider!
    private var mockTokenStore: MockTokenStore!
    private var authService: GoogleAuthService!

    override func setUp() async throws {
        try await super.setUp()
        config = GoogleCalendarConfig()
        mockOAuthProvider = MockOAuthProvider()
        mockTokenStore = MockTokenStore()
        authService = GoogleAuthService(
            config: config,
            oauthProvider: mockOAuthProvider,
            tokenStore: mockTokenStore
        )
    }

    func testSignInTriggersOAuthProvider() async throws {
        try await authService.signIn(presentingWindow: nil)

        let callCount = await mockOAuthProvider.signInCallCount
        XCTAssertEqual(callCount, 1)
    }

    func testSignInStoresTokens() async throws {
        try await authService.signIn(presentingWindow: nil)

        let saveCount = mockTokenStore.saveCallCount
        XCTAssertEqual(saveCount, 1)

        let tokens = try mockTokenStore.retrieve()
        XCTAssertNotNil(tokens)
        XCTAssertEqual(tokens?.accessToken, "mock-access-token")
        XCTAssertEqual(tokens?.refreshToken, "mock-refresh-token")
    }

    func testSignOutClearsTokenStore() async throws {
        try await authService.signIn(presentingWindow: nil)
        try await authService.signOut()

        let removeCount = mockTokenStore.removeCallCount
        XCTAssertEqual(removeCount, 1)

        let tokens = try mockTokenStore.retrieve()
        XCTAssertNil(tokens)
    }

    func testIsSignedInReturnsTrueWhenValidTokenExists() async throws {
        try await authService.signIn(presentingWindow: nil)
        let signedIn = await authService.isSignedIn
        XCTAssertTrue(signedIn)
    }

    func testIsSignedInReturnsFalseWhenNoToken() async throws {
        let signedIn = await authService.isSignedIn
        XCTAssertFalse(signedIn)
    }

    func testIsSignedInReturnsFalseAfterSignOut() async throws {
        try await authService.signIn(presentingWindow: nil)
        try await authService.signOut()
        let signedIn = await authService.isSignedIn
        XCTAssertFalse(signedIn)
    }

    func testFreshAccessTokenReturnsCachedTokenWhenNotExpired() async throws {
        try await authService.signIn(presentingWindow: nil)
        let token = try await authService.freshAccessToken()
        XCTAssertEqual(token, "mock-access-token")
    }

    func testFreshAccessTokenRefreshesWhenExpired() async throws {
        let expiredTokens = OAuthTokens(
            accessToken: "expired-token",
            refreshToken: "mock-refresh-token",
            expiresAt: Date().addingTimeInterval(-60),
            idToken: nil,
            userEmail: "test@example.com"
        )
        mockTokenStore.setTokens(expiredTokens)
        // Also set the auth service's in-memory cache
        await authService.setCachedTokens(expiredTokens)

        let token = try await authService.freshAccessToken()
        XCTAssertEqual(token, "refreshed-access-token")

        let refreshCount = await mockOAuthProvider.refreshCallCount
        XCTAssertEqual(refreshCount, 1)
    }

    func testFreshAccessTokenThrowsWhenNotSignedIn() async {
        do {
            _ = try await authService.freshAccessToken()
            XCTFail("Expected error")
        } catch {
            guard let authError = error as? GoogleAuthError else {
                XCTFail("Unexpected error type: \(error)")
                return
            }
            if case .notSignedIn = authError {
                // Expected
            } else {
                XCTFail("Expected notSignedIn error, got \(authError)")
            }
        }
    }

    func testSignInUserCancellationDoesNotThrow() async throws {
        await mockOAuthProvider.setResult(shouldSucceed: false, shouldCancel: true)

        do {
            try await authService.signIn(presentingWindow: nil)
        } catch let error as GoogleAuthError {
            if case .userCancelled = error {
                // User cancelled is expected to be thrown
                return
            }
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUserEmailAvailableAfterSignIn() async throws {
        try await authService.signIn(presentingWindow: nil)
        let email = await authService.userEmail
        XCTAssertEqual(email, "test@example.com")
    }

    func testUserEmailNilAfterSignOut() async throws {
        try await authService.signIn(presentingWindow: nil)
        try await authService.signOut()
        let email = await authService.userEmail
        XCTAssertNil(email)
    }
}
