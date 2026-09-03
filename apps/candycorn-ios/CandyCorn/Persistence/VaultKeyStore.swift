import Foundation
import Security

protocol VaultKeyProviding: Sendable {
    func getOrCreateKey() throws -> Data
    func deleteKey() throws
}

enum VaultKeyStoreError: Error, Equatable, Sendable {
    case randomGenerationFailed
    case invalidStoredKey
    case keychainFailure
}

final class VaultKeyStore: VaultKeyProviding, @unchecked Sendable {
    static let keyByteCount = 32
    static let service = "dev.candycorn.app.vault"
    static let account = "care-vault-key-v1"

    func getOrCreateKey() throws -> Data {
        if let existing = try readKey() {
            guard existing.count == Self.keyByteCount else { throw VaultKeyStoreError.invalidStoredKey }
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: Self.keyByteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw VaultKeyStoreError.randomGenerationFailed
        }
        let key = Data(bytes)
        let status = SecItemAdd(Self.addQuery(key) as CFDictionary, nil)
        if status == errSecDuplicateItem, let existing = try readKey(), existing.count == Self.keyByteCount {
            return existing
        }
        guard status == errSecSuccess else { throw VaultKeyStoreError.keychainFailure }
        return key
    }

    func deleteKey() throws {
        let status = SecItemDelete(Self.lookupQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultKeyStoreError.keychainFailure
        }
    }

    private func readKey() throws -> Data? {
        var result: CFTypeRef?
        var query = Self.lookupQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw VaultKeyStoreError.keychainFailure
        }
        return data
    }

    private static var lookupQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    private static func addQuery(_ key: Data) -> [String: Any] {
        var query = lookupQuery
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecValueData as String] = key
        return query
    }
}

final class InMemoryVaultKeyStore: VaultKeyProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var key: Data?

    init(key: Data? = nil) {
        self.key = key
    }

    func getOrCreateKey() throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        if let key {
            guard key.count == VaultKeyStore.keyByteCount else { throw VaultKeyStoreError.invalidStoredKey }
            return key
        }
        var bytes = [UInt8](repeating: 0, count: VaultKeyStore.keyByteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw VaultKeyStoreError.randomGenerationFailed
        }
        let generated = Data(bytes)
        key = generated
        return generated
    }

    func deleteKey() throws {
        lock.lock()
        key = nil
        lock.unlock()
    }
}
