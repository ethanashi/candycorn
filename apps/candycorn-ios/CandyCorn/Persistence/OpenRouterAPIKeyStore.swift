import Foundation
import Security

enum OpenRouterAPIKeyStoreError: Error, Equatable, Sendable {
    case invalidKey
    case invalidStoredKey
    case keychainFailure(status: Int32)
}

struct OpenRouterKeychainLookup: Equatable, Sendable {
    let service: String
    let account: String
    let synchronizable: Bool
}

struct OpenRouterKeychainItem: Equatable, Sendable {
    let lookup: OpenRouterKeychainLookup
    let accessibility: String
    let value: Data
}

struct OpenRouterKeychainReadResult: Equatable, Sendable {
    let status: Int32
    let value: Data?
}

protocol OpenRouterKeychainClient: Sendable {
    func read(_ lookup: OpenRouterKeychainLookup) -> OpenRouterKeychainReadResult
    func add(_ item: OpenRouterKeychainItem) -> Int32
    func update(_ lookup: OpenRouterKeychainLookup, value: Data) -> Int32
    func delete(_ lookup: OpenRouterKeychainLookup) -> Int32
}

struct SecurityOpenRouterKeychainClient: OpenRouterKeychainClient {
    func read(_ lookup: OpenRouterKeychainLookup) -> OpenRouterKeychainReadResult {
        var result: CFTypeRef?
        var query = Self.query(for: lookup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            return OpenRouterKeychainReadResult(status: status, value: nil)
        }
        guard let data = result as? Data else {
            return OpenRouterKeychainReadResult(status: errSecDecode, value: nil)
        }
        return OpenRouterKeychainReadResult(status: status, value: data)
    }

    func add(_ item: OpenRouterKeychainItem) -> Int32 {
        var query = Self.query(for: item.lookup)
        query[kSecAttrAccessible as String] = item.accessibility
        query[kSecValueData as String] = item.value
        return SecItemAdd(query as CFDictionary, nil)
    }

    func update(_ lookup: OpenRouterKeychainLookup, value: Data) -> Int32 {
        let attributes = [kSecValueData as String: value]
        return SecItemUpdate(Self.query(for: lookup) as CFDictionary, attributes as CFDictionary)
    }

    func delete(_ lookup: OpenRouterKeychainLookup) -> Int32 {
        SecItemDelete(Self.query(for: lookup) as CFDictionary)
    }

    private static func query(for lookup: OpenRouterKeychainLookup) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: lookup.service,
            kSecAttrAccount as String: lookup.account,
            kSecAttrSynchronizable as String: lookup.synchronizable ? kCFBooleanTrue as Any : kCFBooleanFalse as Any,
        ]
    }
}

struct OpenRouterAPIKeyStore: OpenRouterAPIKeyProviding {
    static let service = "dev.candycorn.app.openrouter"
    static let account = "openrouter-api-key-v1"
    static let maximumCharacterCount = 512
    static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String

    private let client: any OpenRouterKeychainClient

    init(client: any OpenRouterKeychainClient = SecurityOpenRouterKeychainClient()) {
        self.client = client
    }

    func readKey() throws -> String? {
        let result = client.read(Self.lookup)
        if result.status == errSecItemNotFound { return nil }
        guard result.status == errSecSuccess, let data = result.value else {
            throw OpenRouterAPIKeyStoreError.keychainFailure(status: result.status)
        }
        guard let value = String(data: data, encoding: .utf8), Self.isValid(value) else {
            throw OpenRouterAPIKeyStoreError.invalidStoredKey
        }
        return value
    }

    func storeKey(_ value: String) throws {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValid(normalized), let data = normalized.data(using: .utf8) else {
            throw OpenRouterAPIKeyStoreError.invalidKey
        }
        let item = OpenRouterKeychainItem(lookup: Self.lookup, accessibility: Self.accessibility, value: data)
        let addStatus = client.add(item)
        if addStatus == errSecSuccess { return }
        guard addStatus == errSecDuplicateItem else {
            throw OpenRouterAPIKeyStoreError.keychainFailure(status: addStatus)
        }
        let updateStatus = client.update(Self.lookup, value: data)
        guard updateStatus == errSecSuccess else {
            throw OpenRouterAPIKeyStoreError.keychainFailure(status: updateStatus)
        }
    }

    func removeKey() throws {
        let status = client.delete(Self.lookup)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OpenRouterAPIKeyStoreError.keychainFailure(status: status)
        }
    }

    func hasKey() throws -> Bool {
        try readKey() != nil
    }

    private static let lookup = OpenRouterKeychainLookup(
        service: service,
        account: account,
        synchronizable: false
    )

    private static func isValid(_ value: String) -> Bool {
        !value.isEmpty && value.count <= maximumCharacterCount
    }
}

final class InMemoryOpenRouterAPIKeyStore: OpenRouterAPIKeyProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    init() {
        value = nil
    }

    init(key: String) throws {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= OpenRouterAPIKeyStore.maximumCharacterCount else {
            throw OpenRouterAPIKeyStoreError.invalidKey
        }
        value = normalized
    }

    func readKey() throws -> String? {
        lock.withLock { value }
    }

    func storeKey(_ value: String) throws {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= OpenRouterAPIKeyStore.maximumCharacterCount else {
            throw OpenRouterAPIKeyStoreError.invalidKey
        }
        lock.withLock { self.value = normalized }
    }

    func removeKey() throws {
        lock.withLock { value = nil }
    }

    func hasKey() throws -> Bool {
        lock.withLock { value != nil }
    }
}
