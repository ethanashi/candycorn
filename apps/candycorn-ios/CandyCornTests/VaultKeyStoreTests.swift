import Foundation
import Testing
@testable import CandyCorn

@Suite("Vault key store")
struct VaultKeyStoreTests {
    @Test("Repeated and concurrent reads return one 256-bit key")
    func stableKey() async throws {
        let store = InMemoryVaultKeyStore()
        let first = try store.getOrCreateKey()
        let keys = try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<16 { group.addTask { try store.getOrCreateKey() } }
            var values: [Data] = []
            for try await value in group { values.append(value) }
            return values
        }
        #expect(first.count == 32)
        #expect(VaultKeyStore.service == "dev.candycorn.app.vault")
        #expect(VaultKeyStore.account == "care-vault-key-v1")
        #expect(keys.count == 16)
        #expect(keys.allSatisfy { $0 == first })
    }

    @Test("Deleting rotates the in-memory key")
    func rotatesKey() throws {
        let store = InMemoryVaultKeyStore()
        let first = try store.getOrCreateKey()
        try store.deleteKey()
        let second = try store.getOrCreateKey()
        #expect(second.count == 32)
        #expect(first != second)
    }

    @Test("Invalid stored key lengths are rejected")
    func rejectsInvalidLength() {
        let store = InMemoryVaultKeyStore(key: Data(repeating: 0, count: 31))
        #expect(throws: VaultKeyStoreError.invalidStoredKey) { _ = try store.getOrCreateKey() }
    }
}
