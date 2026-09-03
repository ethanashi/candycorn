import Foundation
import Testing
@testable import CandyCorn

@Suite("Vault search")
struct VaultSearchTests {
    @Test("FTS handles punctuation and returns stable newest-first hits")
    func fts() async throws {
        let (root, _, store, _, _) = try VaultTestSupport.make()
        defer { VaultTestSupport.remove(root) }
        _ = try await store.snapshot()
        let hits = try await store.search(" football AND guilt's ", limit: 20)
        #expect(!hits.isEmpty)
        #expect(hits.contains { $0.entityID == SeededData.footballJournalID })
        #expect(hits == hits.sorted { $0.occurredAt > $1.occurredAt })
        #expect(try await store.search("!!!", limit: 20).isEmpty)
        await #expect(throws: VaultRepositoryError.self) { _ = try await store.search(" ", limit: 20) }
        await #expect(throws: VaultRepositoryError.self) { _ = try await store.search("football", limit: 101) }
    }

    @Test("LIKE fallback matches FTS results")
    func fallback() async throws {
        let (ftsRoot, _, fts, _, _) = try VaultTestSupport.make(name: "fts-\(UUID().uuidString)")
        let (likeRoot, _, like, _, _) = try VaultTestSupport.make(name: "like-\(UUID().uuidString)", includeSearch: false)
        defer { VaultTestSupport.remove(ftsRoot); VaultTestSupport.remove(likeRoot) }
        _ = try await fts.snapshot()
        _ = try await like.snapshot()
        let ftsIDs = try await fts.search("football", limit: 20).map(\.id)
        let likeIDs = try await like.search("football", limit: 20).map(\.id)
        #expect(ftsIDs == likeIDs)
    }
}
