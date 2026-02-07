import Foundation
import Security

public protocol KeychainServiceProtocol: Sendable {
    func save(apiKey: String, for providerId: String) throws
    func retrieve(for providerId: String) throws -> String?
    func delete(for providerId: String) throws
    func listProviderIds() throws -> [String]
}

public final class KeychainService: KeychainServiceProtocol, Sendable {
    private let serviceName: String

    public init(serviceName: String = "com.gophy.api-keys") {
        self.serviceName = serviceName
    }

    public func save(apiKey: String, for providerId: String) throws {
        guard let data = apiKey.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let existing = try retrieve(for: providerId)
        if existing != nil {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: providerId
            ]
            let update: [String: Any] = [
                kSecValueData as String: data
            ]
            let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard status == errSecSuccess else {
                throw KeychainError.operationFailed(status)
            }
        } else {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: providerId,
                kSecValueData as String: data
            ]
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw KeychainError.operationFailed(status)
            }
        }
    }

    public func retrieve(for providerId: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: providerId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.operationFailed(status)
        }

        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }

        return string
    }

    public func delete(for providerId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: providerId
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.operationFailed(status)
        }
    }

    public func listProviderIds() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return []
        }

        guard status == errSecSuccess else {
            throw KeychainError.operationFailed(status)
        }

        guard let items = result as? [[String: Any]] else {
            return []
        }

        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }
}

public enum KeychainError: Error, Sendable {
    case encodingFailed
    case decodingFailed
    case operationFailed(OSStatus)
}
