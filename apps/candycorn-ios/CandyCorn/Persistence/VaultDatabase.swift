import Foundation
import GRDB

enum VaultDatabaseError: Error, Equatable, Sendable {
    case unavailable
    case cipherUnavailable
    case recreationFailed
}

struct VaultDatabaseFailure: Error, @unchecked Sendable {
    let category: VaultDatabaseError
    let underlying: any Error
}

actor VaultDatabase: VaultMaintenance {
    let databaseURL: URL
    private let keyStore: any VaultKeyProviding
    private let attachmentStore: (any AttachmentStore)?
    private let logger: any EventLogging
    private let fileManager: FileManager
    private let includeSearch: Bool
    private var queue: DatabaseQueue?

    init(
        databaseURL: URL,
        keyStore: any VaultKeyProviding,
        attachmentStore: (any AttachmentStore)? = nil,
        logger: any EventLogging = PrivacyEventLogger(),
        fileManager: FileManager = .default,
        includeSearch: Bool = true
    ) {
        self.databaseURL = databaseURL.standardizedFileURL
        self.keyStore = keyStore
        self.attachmentStore = attachmentStore
        self.logger = logger
        self.fileManager = fileManager
        self.includeSearch = includeSearch
    }

    static func applicationSupport(
        keyStore: any VaultKeyProviding = VaultKeyStore(),
        attachmentStore: (any AttachmentStore)? = nil,
        logger: any EventLogging = PrivacyEventLogger()
    ) throws -> VaultDatabase {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw VaultDatabaseError.unavailable
        }
        let url = support.appending(path: "CandyCorn/care.db")
        return VaultDatabase(databaseURL: url, keyStore: keyStore, attachmentStore: attachmentStore, logger: logger)
    }

    func open() throws {
        if queue != nil { return }
        let parentURL = databaseURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        try Self.applyProtection(to: parentURL)
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.journalMode = .wal
        configuration.prepareDatabase { [keyStore] db in
            var key = try keyStore.getOrCreateKey()
            defer { key.resetBytes(in: 0..<key.count) }
            try db.usePassphrase(key)
        }
        do {
            let opened = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
            try VaultMigrations.makeMigrator(includeSearch: includeSearch).migrate(opened)
            let cipher = try opened.read { db in try String.fetchOne(db, sql: "PRAGMA cipher_version") }
            guard let cipher, !cipher.isEmpty else { throw VaultDatabaseError.cipherUnavailable }
            for url in databaseFiles() where fileManager.fileExists(atPath: url.path) {
                try Self.applyProtection(to: url)
            }
            queue = opened
            logger.record(.migrationCompleted, metrics: EventMetrics())
        } catch let error as VaultDatabaseError {
            throw error
        } catch {
            throw VaultDatabaseFailure(category: .unavailable, underlying: error)
        }
    }

    func close() {
        queue = nil
    }

    func read<Value: Sendable>(_ body: @Sendable (Database) throws -> Value) throws -> Value {
        try open()
        guard let queue else { throw VaultDatabaseError.unavailable }
        return try queue.read(body)
    }

    func write<Value: Sendable>(_ body: @Sendable (Database) throws -> Value) throws -> Value {
        try open()
        guard let queue else { throw VaultDatabaseError.unavailable }
        return try queue.write(body)
    }

    func cipherVersion() throws -> String {
        try read { db in
            guard let version = try String.fetchOne(db, sql: "PRAGMA cipher_version"), !version.isEmpty else {
                throw VaultDatabaseError.cipherUnavailable
            }
            return version
        }
    }

    func appliedMigrations() throws -> [String] {
        try read { db in
            try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid")
        }
    }

    func destroyAndRecreateVault() async throws {
        queue = nil
        do {
            for url in databaseFiles() where fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            if let attachmentStore { try await attachmentStore.removeAll() }
            try keyStore.deleteKey()
            try open()
            let settings = VaultSettings(useSampleContent: false, audioRetention: .ask, aiMode: .off, aiProvider: .off)
            let payload = try PersistenceCoding.encode(settings)
            try write { db in
                try db.execute(
                    sql: "INSERT OR REPLACE INTO app_settings (id, use_sample_content, payload) VALUES (1, 0, ?)",
                    arguments: [payload]
                )
            }
            logger.record(.vaultDeleted, metrics: EventMetrics())
        } catch {
            queue = nil
            throw VaultDatabaseFailure(category: .recreationFailed, underlying: error)
        }
    }

    private func databaseFiles() -> [URL] {
        [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm"),
            URL(fileURLWithPath: databaseURL.path + "-journal"),
        ]
    }

    private static func applyProtection(to url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try (url as NSURL).setResourceValue(URLFileProtection.completeUntilFirstUserAuthentication, forKey: .fileProtectionKey)
    }
}
