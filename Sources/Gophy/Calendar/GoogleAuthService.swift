import Foundation
import os.log
import AppAuthCore
import AppAuth
import GTMAppAuth

private let logger = Logger(subsystem: "com.gophy.app", category: "GoogleAuth")

// MARK: - Error Types

enum GoogleAuthError: Error, LocalizedError, Sendable {
    case notSignedIn
    case userCancelled
    case authorizationFailed(String)
    case tokenRefreshFailed(String)
    case keychainError(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in to Google. Please sign in first."
        case .userCancelled:
            return "Sign-in was cancelled."
        case .authorizationFailed(let message):
            return "Authorization failed: \(message)"
        case .tokenRefreshFailed(let message):
            return "Token refresh failed: \(message)"
        case .keychainError(let message):
            return "Keychain error: \(message)"
        }
    }
}

// MARK: - Token Models

struct OAuthTokens: Codable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
    let idToken: String?
    let userEmail: String?

    var isExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-60)
    }
}

// MARK: - Protocols for Testability

protocol OAuthProviderProtocol: Sendable {
    func signIn(
        config: GoogleCalendarConfig,
        presentingWindow: sending AnyObject?
    ) async throws -> OAuthTokens

    func refreshAccessToken(
        refreshToken: String,
        config: GoogleCalendarConfig
    ) async throws -> OAuthTokens
}

protocol TokenStoreProtocol: Sendable {
    func save(_ tokens: OAuthTokens) throws
    func retrieve() throws -> OAuthTokens?
    func remove() throws
}

// MARK: - AppAuth OAuth Provider

final class AppAuthOAuthProvider: OAuthProviderProtocol {

    @MainActor
    private func performSignIn(
        config: GoogleCalendarConfig
    ) async throws -> OAuthTokens {
        let configuration = AuthSession.configurationForGoogle()

        let redirectHandler = OIDRedirectHTTPHandler(successURL: nil)

        var listenerError: NSError?
        let redirectURI = redirectHandler.startHTTPListener(&listenerError)
        if let listenerError {
            throw GoogleAuthError.authorizationFailed("Failed to start loopback HTTP listener: \(listenerError.localizedDescription)")
        }

        let clientSecret = GoogleCalendarConfig.clientSecret.isEmpty ? nil : GoogleCalendarConfig.clientSecret

        let request = OIDAuthorizationRequest(
            configuration: configuration,
            clientId: GoogleCalendarConfig.clientID,
            clientSecret: clientSecret,
            scopes: config.scopes,
            redirectURL: redirectURI,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<OAuthTokens, Error>) in
            redirectHandler.currentAuthorizationFlow = OIDAuthState.authState(
                byPresenting: request,
                callback: { authState, error in
                    redirectHandler.cancelHTTPListener()

                    if let error = error as NSError? {
                        if error.domain == OIDGeneralErrorDomain,
                           error.code == OIDErrorCode.userCanceledAuthorizationFlow.rawValue {
                            continuation.resume(throwing: GoogleAuthError.userCancelled)
                            return
                        }
                        continuation.resume(throwing: GoogleAuthError.authorizationFailed(error.localizedDescription))
                        return
                    }

                    guard let authState = authState,
                          let accessToken = authState.lastTokenResponse?.accessToken else {
                        continuation.resume(throwing: GoogleAuthError.authorizationFailed("No auth state returned"))
                        return
                    }

                    let expiresAt = authState.lastTokenResponse?.accessTokenExpirationDate ?? Date().addingTimeInterval(3600)
                    let refreshToken = authState.refreshToken
                    let idToken = authState.lastTokenResponse?.idToken

                    var email: String?
                    if let idTokenString = idToken {
                        email = Self.extractEmail(fromIDToken: idTokenString)
                    }

                    let tokens = OAuthTokens(
                        accessToken: accessToken,
                        refreshToken: refreshToken,
                        expiresAt: expiresAt,
                        idToken: idToken,
                        userEmail: email
                    )
                    continuation.resume(returning: tokens)
                }
            )
        }
    }

    func signIn(
        config: GoogleCalendarConfig,
        presentingWindow: sending AnyObject?
    ) async throws -> OAuthTokens {
        return try await performSignIn(config: config)
    }

    func refreshAccessToken(
        refreshToken: String,
        config: GoogleCalendarConfig
    ) async throws -> OAuthTokens {
        let configuration = AuthSession.configurationForGoogle()

        let clientSecret = GoogleCalendarConfig.clientSecret.isEmpty ? nil : GoogleCalendarConfig.clientSecret

        let tokenRequest = OIDTokenRequest(
            configuration: configuration,
            grantType: OIDGrantTypeRefreshToken,
            authorizationCode: nil,
            redirectURL: GoogleCalendarConfig.loopbackRedirectURI,
            clientID: GoogleCalendarConfig.clientID,
            clientSecret: clientSecret,
            scope: nil,
            refreshToken: refreshToken,
            codeVerifier: nil,
            additionalParameters: nil
        )

        return try await withCheckedThrowingContinuation { continuation in
            OIDAuthorizationService.perform(tokenRequest) { tokenResponse, error in
                if let error = error {
                    continuation.resume(throwing: GoogleAuthError.tokenRefreshFailed(error.localizedDescription))
                    return
                }

                guard let tokenResponse = tokenResponse,
                      let accessToken = tokenResponse.accessToken else {
                    continuation.resume(throwing: GoogleAuthError.tokenRefreshFailed("No token response"))
                    return
                }

                let expiresAt = tokenResponse.accessTokenExpirationDate ?? Date().addingTimeInterval(3600)

                var email: String?
                if let idToken = tokenResponse.idToken {
                    email = Self.extractEmail(fromIDToken: idToken)
                }

                let tokens = OAuthTokens(
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    expiresAt: expiresAt,
                    idToken: tokenResponse.idToken,
                    userEmail: email
                )
                continuation.resume(returning: tokens)
            }
        }
    }

    private static func extractEmail(fromIDToken idToken: String) -> String? {
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var base64 = String(parts[1])
        while base64.count % 4 != 0 {
            base64 += "="
        }
        base64 = base64
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String else {
            return nil
        }
        return email
    }
}

// MARK: - Keychain Token Store

final class KeychainTokenStore: TokenStoreProtocol {
    private let itemName: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(itemName: String = GoogleCalendarConfig.keychainItemName) {
        self.itemName = itemName
    }

    func save(_ tokens: OAuthTokens) throws {
        let data = try encoder.encode(tokens)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: itemName,
            kSecAttrAccount as String: "google-oauth-tokens",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecUseDataProtectionKeychain as String: false
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw GoogleAuthError.keychainError("Failed to save tokens: \(status)")
        }
    }

    func retrieve() throws -> OAuthTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: itemName,
            kSecAttrAccount as String: "google-oauth-tokens",
            kSecReturnData as String: true,
            kSecUseDataProtectionKeychain as String: false
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess, let data = result as? Data else {
            throw GoogleAuthError.keychainError("Failed to retrieve tokens: \(status)")
        }

        return try decoder.decode(OAuthTokens.self, from: data)
    }

    func remove() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: itemName,
            kSecAttrAccount as String: "google-oauth-tokens",
            kSecUseDataProtectionKeychain as String: false
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GoogleAuthError.keychainError("Failed to remove tokens: \(status)")
        }
    }
}

// MARK: - GoogleAuthService

actor GoogleAuthService {
    private let config: GoogleCalendarConfig
    private let oauthProvider: any OAuthProviderProtocol
    private let tokenStore: any TokenStoreProtocol
    private var cachedTokens: OAuthTokens?

    init(
        config: GoogleCalendarConfig,
        oauthProvider: any OAuthProviderProtocol = AppAuthOAuthProvider(),
        tokenStore: any TokenStoreProtocol = KeychainTokenStore()
    ) {
        self.config = config
        self.oauthProvider = oauthProvider
        self.tokenStore = tokenStore

        if let tokens = try? tokenStore.retrieve() {
            self.cachedTokens = tokens
        }
    }

    var isSignedIn: Bool {
        cachedTokens != nil
    }

    var userEmail: String? {
        cachedTokens?.userEmail
    }

    func signIn(presentingWindow: sending AnyObject?) async throws {
        logger.info("Starting Google sign-in flow")
        let pw: AnyObject? = presentingWindow

        let tokens = try await oauthProvider.signIn(
            config: config,
            presentingWindow: pw
        )

        try tokenStore.save(tokens)
        cachedTokens = tokens

        logger.info("Google sign-in successful for \(tokens.userEmail ?? "unknown", privacy: .public)")
    }

    func signOut() throws {
        logger.info("Signing out of Google")
        try tokenStore.remove()
        cachedTokens = nil
        logger.info("Google sign-out complete")
    }

    func freshAccessToken() async throws -> String {
        guard var tokens = cachedTokens else {
            throw GoogleAuthError.notSignedIn
        }

        if tokens.isExpired {
            guard let refreshToken = tokens.refreshToken else {
                cachedTokens = nil
                try? tokenStore.remove()
                throw GoogleAuthError.notSignedIn
            }

            logger.info("Access token expired, refreshing")
            let refreshedTokens = try await oauthProvider.refreshAccessToken(
                refreshToken: refreshToken,
                config: config
            )

            try tokenStore.save(refreshedTokens)
            cachedTokens = refreshedTokens
            tokens = refreshedTokens
            logger.info("Token refreshed successfully")
        }

        return tokens.accessToken
    }

    func setCachedTokens(_ tokens: OAuthTokens?) {
        cachedTokens = tokens
    }
}
