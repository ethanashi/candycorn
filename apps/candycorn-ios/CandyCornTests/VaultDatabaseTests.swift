import Foundation
import GRDB
import Testing
@testable import CandyCorn

enum VaultTestSupport {
    static func make(name: String = UUID().uuidString, includeSearch: Bool = true) throws -> (URL, VaultDatabase, VaultRepositories, VaultAttachmentStore, InMemoryVaultKeyStore) {
        let root = FileManager.default.temporaryDirectory.appending(path: "candycorn-vault-tests/\(name)", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let keyStore = InMemoryVaultKeyStore()
        let attachments = try VaultAttachmentStore(rootURL: root.appending(path: "attachments", directoryHint: .isDirectory))
        let database = VaultDatabase(databaseURL: root.appending(path: "care.db"), keyStore: keyStore, attachmentStore: attachments, logger: NoOpEventLogger(), includeSearch: includeSearch)
        let repositories = VaultRepositories(database: database, attachments: attachments, logger: NoOpEventLogger())
        return (root, database, repositories, attachments, keyStore)
    }

    static func remove(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    static func rawQueue(url: URL, key: Data) throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.prepareDatabase { db in try db.usePassphrase(key) }
        return try DatabaseQueue(path: url.path, configuration: configuration)
    }
}

@Suite("Vault database")
struct VaultDatabaseTests {
    @Test("Open creates an encrypted, migrated database")
    func opensEncryptedDatabase() async throws {
        let (root, database, _, _, _) = try VaultTestSupport.make()
        defer { VaultTestSupport.remove(root) }
        try await database.open()
        #expect(!(try await database.cipherVersion()).isEmpty)
        #expect(try await database.appliedMigrations() == ["v1_core", "v2_relations", "v3_search", "v4_appointment_audio", VaultMigrations.latestIdentifier])
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "care.db").path))
    }

    @Test("A wrong key cannot read a copied vault")
    func rejectsWrongKey() async throws {
        let (root, database, _, _, _) = try VaultTestSupport.make()
        defer { VaultTestSupport.remove(root) }
        try await database.open()
        await database.close()
        let wrong = InMemoryVaultKeyStore(key: Data(repeating: 0xA5, count: 32))
        let wrongDatabase = VaultDatabase(databaseURL: root.appending(path: "care.db"), keyStore: wrong, logger: NoOpEventLogger())
        var rejected = false
        do { try await wrongDatabase.open() } catch { rejected = true }
        #expect(rejected)
    }
}
