// Services/Configuration/APIKeyStore.swift

import Foundation
import Security

/// Where the user's Gemini API key is kept. The live app uses the Keychain;
/// previews and tests use memory.
protocol APIKeyStoring: Sendable {
    func load() throws(KeychainError) -> String?
    func save(_ key: String) throws(KeychainError)
    func delete() throws(KeychainError)
}

struct KeychainError: Error, Equatable, Sendable, LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
        return "The Keychain couldn't store the API key (\(message))."
    }
}

/// Stores the key as a generic password that stays on this device: it isn't
/// synced to iCloud Keychain or restored onto another phone.
struct KeychainAPIKeyStore: APIKeyStoring {
    static let defaultService = (Bundle.main.bundleIdentifier ?? "MacroDepth") + ".gemini"

    let service: String
    let account: String

    init(service: String = KeychainAPIKeyStore.defaultService, account: String = "api-key") {
        self.service = service
        self.account = account
    }

    func load() throws(KeychainError) -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return (result as? Data).flatMap { String(data: $0, encoding: .utf8) }
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    func save(_ key: String) throws(KeychainError) {
        let data = Data(key.utf8)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = baseQuery
            item.merge(update) { _, new in new }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        default:
            throw KeychainError(status: status)
        }
    }

    func delete() throws(KeychainError) {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// For previews and tests.
final class InMemoryAPIKeyStore: APIKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?

    init(key: String? = nil) {
        self.key = key
    }

    func load() throws(KeychainError) -> String? {
        lock.withLock { key }
    }

    func save(_ key: String) throws(KeychainError) {
        lock.withLock { self.key = key }
    }

    func delete() throws(KeychainError) {
        lock.withLock { key = nil }
    }
}
