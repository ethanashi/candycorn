import Foundation
import Security
import Testing
@testable import CandyCorn

@Suite("OpenRouter API key persistence")
struct OpenRouterAPIKeyPersistenceTests {
    @Test("Keychain item uses the private device-only contract and updates in place")
    func keychainContractAndLifecycle() throws {
        let client = RecordingOpenRouterKeychainClient()
        let store = OpenRouterAPIKeyStore(client: client)

        #expect(try store.readKey() == nil)
        #expect(try !store.hasKey())
        try store.storeKey("  test-secret-one\n")

        let firstItem = try #require(client.addedItems.first)
        #expect(firstItem.lookup.service == "dev.candycorn.app.openrouter")
        #expect(firstItem.lookup.account == "openrouter-api-key-v1")
        #expect(!firstItem.lookup.synchronizable)
        #expect(firstItem.accessibility == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(firstItem.value == Data("test-secret-one".utf8))
        #expect(try store.readKey() == "test-secret-one")
        #expect(try store.hasKey())

        try store.storeKey("test-secret-two")
        #expect(client.updateValues == [Data("test-secret-two".utf8)])
        #expect(try store.readKey() == "test-secret-two")

        try store.removeKey()
        try store.removeKey()
        #expect(try store.readKey() == nil)
        #expect(try !store.hasKey())
        #expect(client.deletedLookups.count == 2)
    }

    @Test("Invalid keys and invalid stored UTF-8 fail without exposing values")
    func invalidValues() throws {
        let client = RecordingOpenRouterKeychainClient()
        let store = OpenRouterAPIKeyStore(client: client)

        #expect(throws: OpenRouterAPIKeyStoreError.invalidKey) { try store.storeKey(" \n\t ") }
        #expect(throws: OpenRouterAPIKeyStoreError.invalidKey) {
            try store.storeKey(String(repeating: "x", count: OpenRouterAPIKeyStore.maximumCharacterCount + 1))
        }

        client.setStoredValue(Data([0xff, 0xfe]))
        #expect(throws: OpenRouterAPIKeyStoreError.invalidStoredKey) { _ = try store.readKey() }

        client.readStatus = errSecInteractionNotAllowed
        #expect(throws: OpenRouterAPIKeyStoreError.keychainFailure(status: errSecInteractionNotAllowed)) {
            _ = try store.readKey()
        }

        client.readStatus = errSecSuccess
        client.setStoredValue(nil)
        client.addStatus = errSecNotAvailable
        #expect(throws: OpenRouterAPIKeyStoreError.keychainFailure(status: errSecNotAvailable)) {
            try store.storeKey("never-returned-in-the-error")
        }
    }

    @Test("In-memory storage matches save, read, presence, and idempotent removal")
    func inMemoryStore() throws {
        let store = InMemoryOpenRouterAPIKeyStore()
        #expect(try !store.hasKey())
        try store.storeKey(" no-prefix-required ")
        #expect(try store.readKey() == "no-prefix-required")
        try store.removeKey()
        try store.removeKey()
        #expect(try !store.hasKey())
    }

    @Test("In-memory storage supports concurrent trusted reads")
    func concurrentReads() async throws {
        let store = InMemoryOpenRouterAPIKeyStore()
        try store.storeKey("concurrent-test-key")

        try await withThrowingTaskGroup(of: String?.self) { group in
            for _ in 0..<20 {
                group.addTask { try store.readKey() }
            }
            var resultCount = 0
            for try await result in group {
                #expect(result == "concurrent-test-key")
                resultCount += 1
            }
            #expect(resultCount == 20)
        }
    }
}

@Suite("AI model configuration persistence")
struct AIModelConfigurationPersistenceTests {
    @Test("Absent and corrupt configuration use safe defaults")
    func defaultsAndCorruption() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAIConfigurationStore(defaults: defaults)

        #expect(store.load() == .defaults)
        defaults.set(Data("not-json".utf8), forKey: UserDefaultsAIConfigurationStore.storageKey)
        #expect(store.load() == .defaults)
    }

    @Test("Configuration trims identifiers, round trips, and resets")
    func roundTripAndReset() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAIConfigurationStore(defaults: defaults)
        let configuration = AIModelConfiguration(
            organizerModelID: "  provider/organizer-model  ",
            visionModelID: "\nprovider/vision-model\t"
        )

        try store.save(configuration)
        #expect(store.load() == AIModelConfiguration(
            organizerModelID: "provider/organizer-model",
            visionModelID: "provider/vision-model"
        ))
        try store.reset()
        #expect(store.load() == .defaults)
    }

    @Test("Configuration rejects missing and oversized model identifiers")
    func validation() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAIConfigurationStore(defaults: defaults)

        #expect(throws: AIConfigurationStoreError.invalidModelIdentifier) {
            try store.save(AIModelConfiguration(organizerModelID: " ", visionModelID: "provider/vision"))
        }
        #expect(throws: AIConfigurationStoreError.invalidModelIdentifier) {
            try store.save(AIModelConfiguration(
                organizerModelID: "provider/organizer",
                visionModelID: String(repeating: "v", count: UserDefaultsAIConfigurationStore.maximumModelIdentifierCount + 1)
            ))
        }
    }

    @Test("Model defaults never receive the OpenRouter key")
    func keyNeverReachesUserDefaults() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let configurationStore = UserDefaultsAIConfigurationStore(defaults: defaults)
        let keyStore = OpenRouterAPIKeyStore(client: RecordingOpenRouterKeychainClient())
        let secret = "sensitive-test-value"

        try keyStore.storeKey(secret)
        try configurationStore.save(.defaults)
        let persistedDescription = String(describing: defaults.persistentDomain(forName: suiteName) ?? [:])
        #expect(!persistedDescription.contains(secret))
        #expect(defaults.object(forKey: UserDefaultsAIConfigurationStore.storageKey) is Data)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "AIConfigurationPersistenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}

private final class RecordingOpenRouterKeychainClient: OpenRouterKeychainClient, @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Data?
    private var items: [OpenRouterKeychainItem] = []
    private var updates: [Data] = []
    private var deletions: [OpenRouterKeychainLookup] = []
    var readStatus: Int32 = errSecSuccess
    var addStatus: Int32?

    var addedItems: [OpenRouterKeychainItem] { lock.withLock { items } }
    var updateValues: [Data] { lock.withLock { updates } }
    var deletedLookups: [OpenRouterKeychainLookup] { lock.withLock { deletions } }

    func setStoredValue(_ value: Data?) {
        lock.withLock { storedValue = value }
    }

    func read(_ lookup: OpenRouterKeychainLookup) -> OpenRouterKeychainReadResult {
        lock.withLock {
            guard readStatus == errSecSuccess else {
                return OpenRouterKeychainReadResult(status: readStatus, value: nil)
            }
            guard let storedValue else {
                return OpenRouterKeychainReadResult(status: errSecItemNotFound, value: nil)
            }
            return OpenRouterKeychainReadResult(status: errSecSuccess, value: storedValue)
        }
    }

    func add(_ item: OpenRouterKeychainItem) -> Int32 {
        lock.withLock {
            items.append(item)
            if let addStatus { return addStatus }
            guard storedValue == nil else { return errSecDuplicateItem }
            storedValue = item.value
            return errSecSuccess
        }
    }

    func update(_ lookup: OpenRouterKeychainLookup, value: Data) -> Int32 {
        lock.withLock {
            guard storedValue != nil else { return errSecItemNotFound }
            updates.append(value)
            storedValue = value
            return errSecSuccess
        }
    }

    func delete(_ lookup: OpenRouterKeychainLookup) -> Int32 {
        lock.withLock {
            deletions.append(lookup)
            guard storedValue != nil else { return errSecItemNotFound }
            storedValue = nil
            return errSecSuccess
        }
    }
}
