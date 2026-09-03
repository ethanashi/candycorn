import Foundation
import GRDB
import Testing
@testable import CandyCorn

@Suite("Vault migrations")
struct VaultMigrationTests {
    @Test("Migrations are repeatable and upgrade v1")
    func upgradesAndRepeats() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "candycorn-migration-\(UUID().uuidString)")
        defer { VaultTestSupport.remove(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let key = Data(repeating: 0x17, count: 32)
        let queue = try VaultTestSupport.rawQueue(url: root.appending(path: "care.db"), key: key)
        let migrator = VaultMigrations.makeMigrator()
        try migrator.migrate(queue, upTo: "v1_core")
        #expect(try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM grdb_migrations") } == 1)
        try migrator.migrate(queue)
        try migrator.migrate(queue)
        #expect(try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM grdb_migrations") } == 4)
    }

    @Test("Foreign keys reject dangling records")
    func foreignKeys() async throws {
        let (root, database, _, _, _) = try VaultTestSupport.make()
        defer { VaultTestSupport.remove(root) }
        var rejected = false
        do {
            try await database.write { db in
                try db.execute(sql: "INSERT INTO goal_progress (id, goal_id, created_at, is_sample, payload) VALUES (?, ?, 0, 0, ?)", arguments: [UUID().uuidString, UUID().uuidString, Data()])
            }
        } catch { rejected = true }
        #expect(rejected)
    }

    @Test("A failed migration rolls back its schema change")
    func rollback() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "candycorn-rollback-\(UUID().uuidString)")
        defer { VaultTestSupport.remove(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let queue = try VaultTestSupport.rawQueue(url: root.appending(path: "care.db"), key: Data(repeating: 0x31, count: 32))
        var failed = false
        do { try VaultMigrations.makeMigrator(forcedFailure: true).migrate(queue) } catch { failed = true }
        #expect(failed)
        let markerCount = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='forced_rollback_marker'")
        }
        #expect(markerCount == 0)
    }
}
