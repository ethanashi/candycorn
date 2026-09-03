import Foundation
import GRDB
import Testing
@testable import CandyCorn

@Suite("AI artifact persistence")
struct AIArtifactPersistenceTests {
    @Test("Artifacts save, replace sources in order, and delete without changing source material")
    func lifecycleAndSourceImmutability() async throws {
        let (root, database, store, _, _) = try VaultTestSupport.make()
        defer { VaultTestSupport.remove(root) }
        let before = try await store.snapshot()
        let artifactID = try #require(UUID(uuidString: "75000000-0000-0000-0000-000000000001"))
        let first = artifact(
            id: artifactID,
            sources: [SeededData.timelineJournalID, SeededData.footballJournalID],
            model: "provider/organizer-v1"
        )

        try await store.saveArtifact(first)
        var snapshot = try await store.snapshot()
        #expect(snapshot.artifacts.contains(first))
        #expect(snapshot.journals == before.journals)
        #expect(snapshot.attachments == before.attachments)
        #expect(try await sourceIDs(for: artifactID, database: database) == first.sourceIDs)

        let replacement = artifact(
            id: artifactID,
            sources: [SeededData.therapySessionID, SeededData.footballJournalID, SeededData.timelineJournalID],
            model: "provider/organizer-v2"
        )
        try await store.saveArtifact(replacement)
        snapshot = try await store.snapshot()
        #expect(snapshot.artifacts.first { $0.id == artifactID } == replacement)
        #expect(try await sourceIDs(for: artifactID, database: database) == replacement.sourceIDs)
        #expect(snapshot.journals == before.journals)
        #expect(snapshot.attachments == before.attachments)

        try await store.deleteArtifact(id: artifactID)
        try await store.deleteArtifact(id: artifactID)
        snapshot = try await store.snapshot()
        #expect(!snapshot.artifacts.contains { $0.id == artifactID })
        #expect(try await sourceIDs(for: artifactID, database: database).isEmpty)
        #expect(snapshot.journals == before.journals)
        #expect(snapshot.attachments == before.attachments)
    }

    @Test("Artifact metadata and structured seed payloads survive persistence")
    func metadataAndSeedPayloads() async throws {
        let (root, _, store, _, _) = try VaultTestSupport.make()
        defer { VaultTestSupport.remove(root) }
        let snapshot = try await store.snapshot()

        let rewrite = try #require(snapshot.artifacts.first { $0.kind == .journalRewrite })
        let signals = try #require(snapshot.artifacts.first { $0.kind == .journalSignals })
        let session = try #require(snapshot.artifacts.first { $0.kind == .sessionSummary })
        let brief = try #require(snapshot.artifacts.first { $0.kind == .appointmentBrief })
        #expect(rewrite.provider == "openrouter")
        #expect(rewrite.model == AIModelConfiguration.defaults.organizerModelID)
        #expect(rewrite.sourceIDs == [SeededData.footballJournalID])
        #expect(try JSONDecoder().decode(RewriteJournalResult.self, from: rewrite.structuredPayload).segments.count == 2)
        #expect(try JSONDecoder().decode(JournalSignalResult.self, from: signals.structuredPayload).signals.explicitCommitments.isEmpty)
        #expect(try JSONDecoder().decode(SessionSummaryResult.self, from: session.structuredPayload).sections.count == 2)
        #expect(try JSONDecoder().decode(AppointmentBriefResult.self, from: brief.structuredPayload).sections.count == 2)
    }

    @Test("Artifact without source identifiers is rejected without a partial row")
    func rejectsMissingSources() async throws {
        let (root, _, store, _, _) = try VaultTestSupport.make()
        defer { VaultTestSupport.remove(root) }
        let noSourceArtifact = artifact(id: UUID(), sources: [], model: "provider/organizer")
        var rejected = false

        do {
            try await store.saveArtifact(noSourceArtifact)
        } catch let error as VaultRepositoryError {
            rejected = error == .invalidInput
        }
        #expect(rejected)
        #expect(!(try await store.snapshot().artifacts.contains { $0.id == noSourceArtifact.id }))
    }

    private func artifact(id: UUID, sources: [UUID], model: String) -> AIArtifact {
        AIArtifact(
            id: id,
            kind: .journalSummary,
            sourceIDs: sources,
            provider: "openrouter",
            model: model,
            structuredPayload: Data("{\"fixture\":true}".utf8),
            createdAt: Date(timeIntervalSince1970: 1_788_700_000)
        )
    }

    private func sourceIDs(for artifactID: UUID, database: VaultDatabase) async throws -> [UUID] {
        try await database.read { db in
            let values = try String.fetchAll(
                db,
                sql: "SELECT source_id FROM ai_artifact_sources WHERE artifact_id = ? ORDER BY position",
                arguments: [artifactID.uuidString.lowercased()]
            )
            return try values.map { value in
                guard let id = UUID(uuidString: value) else { throw VaultRepositoryError.invalidInput }
                return id
            }
        }
    }
}
