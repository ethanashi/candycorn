import Foundation
import Testing
@testable import CandyCorn

@Suite("Vault repositories")
struct VaultRepositoryTests {
    @Test("First open seeds once and sample removal preserves real journals")
    func seedAndSampleRemoval() async throws {
        let (root, _, store, _, _) = try VaultTestSupport.make()
        defer { VaultTestSupport.remove(root) }
        let first = try await store.snapshot()
        let second = try await store.snapshot()
        #expect(Set(first.journals.map(\.id)) == Set(SeededData.journalEntries.map(\.id)))
        #expect(Set(first.moods.map(\.id)) == Set(SeededData.moodLogs.map(\.id)))
        #expect(Set(first.appointments.map(\.id)) == Set(SeededData.appointments.map(\.id)))
        #expect(Set(first.goals.map(\.id)) == Set(SeededData.goals.map(\.id)))
        #expect(Set(first.talkingPoints.map(\.id)) == Set(SeededData.talkingPoints.map(\.id)))
        #expect(Set(first.artifacts.map(\.id)) == Set(SeededData.aiArtifacts.map(\.id)))
        #expect(Set(first.attachments.map(\.id)) == Set(SeededData.attachments.map(\.id)))
        #expect(Set(first.providers.map(\.id)) == Set(SeededData.providers.map(\.id)))
        #expect(Set(first.transcript.map(\.id)) == Set(SeededData.transcript.map(\.id)))
        #expect(second == first)
        let timestamp = Self.date(milliseconds: 1_800_000_000_125)
        let real = JournalEntry(id: UUID(), createdAt: timestamp, updatedAt: timestamp, inputType: .text, title: "A real entry", rawText: "Kept after samples are removed", cleanedText: nil, summaryItems: [], originalAttachmentID: nil, audioAttachmentID: nil, moodLogID: nil, pinnedForNextAppointment: false, processingStatus: .unprocessed, provenance: Provenance(voice: .user, label: "You wrote this", detail: "Journal", occurredAt: timestamp, sourceRoute: .journalDetail))
        try await store.saveJournal(real)
        try await store.setSampleContentEnabled(false)
        let withoutSamples = try await store.snapshot()
        #expect(withoutSamples.journals == [real])
        #expect(!withoutSamples.settings.useSampleContent)
        try await store.setSampleContentEnabled(true)
        let restored = try await store.snapshot()
        #expect(Set(restored.journals.map(\.id)) == Set(SeededData.journalEntries.map(\.id) + [real.id]))
        try await store.setSampleContentEnabled(true)
        #expect(try await store.snapshot() == restored)
    }

    @Test("CRUD persists moods, goals, progress, points, and attachments")
    func crud() async throws {
        let (root, _, store, _, _) = try VaultTestSupport.make()
        defer { VaultTestSupport.remove(root) }
        try await store.setSampleContentEnabled(false)
        let timestamp = Self.date(milliseconds: 1_800_000_001_250)
        let mood = MoodLog(id: UUID(), createdAt: timestamp, mood: 6, anxiety: 4, energy: 7, customValues: ["focus": 8], note: "Steady")
        try await store.saveMood(mood)
        try await store.saveMood(mood)
        let goal = Goal(id: UUID(), title: "Walk after lunch", detail: "Ten minutes", cadence: .daily, source: .userExplicit, sourceEntityID: nil, sourceTimestampMilliseconds: nil, status: .active, createdAt: timestamp, targetDate: nil, provenance: Provenance(voice: .user, label: "You chose this", detail: "Goal", occurredAt: timestamp, sourceRoute: .goals))
        try await store.saveGoal(goal)
        let progress = GoalProgress(id: UUID(), goalID: goal.id, sourceEntryID: nil, note: "Completed today", source: .userConfirmed, createdAt: timestamp)
        try await store.addGoalProgress(progress)
        let point = TalkingPoint(id: UUID(), text: "Ask about sleep", source: .manual, sourceID: nil, targetAppointmentKind: .therapy, isImportant: true, status: .open, createdAt: timestamp, provenance: Provenance(voice: .user, label: "You added this", detail: "Bring up next time", occurredAt: timestamp, sourceRoute: .bringUp))
        try await store.saveTalkingPoint(point)
        let attachment = Attachment(id: UUID(), kind: .audio, relativePath: "audio/test.m4a", mediaType: "audio/mp4", byteCount: 12, durationMilliseconds: 500, createdAt: timestamp, isSample: false)
        try await store.saveAttachment(attachment)
        let snapshot = try await store.snapshot()
        #expect(snapshot.moods == [mood])
        #expect(snapshot.goals == [goal])
        #expect(snapshot.goalProgress == [progress])
        #expect(snapshot.talkingPoints == [point])
        #expect(snapshot.attachments == [attachment])
    }

    @Test("Sample removal preserves every user-owned record")
    func sampleRemovalPreservesUserRecords() async throws {
        let (root, database, store, _, _) = try VaultTestSupport.make()
        defer { VaultTestSupport.remove(root) }
        _ = try await store.snapshot()
        let timestamp = Self.date(milliseconds: 1_800_000_002_500)
        let provider = ProviderProfile(id: UUID(), name: "Dr. Morgan", appointmentKind: .therapy, isSample: false)
        let mood = MoodLog(id: UUID(), createdAt: timestamp, mood: 8, anxiety: nil, energy: 5, customValues: ["focus": 9], note: "Ready")
        let attachment = Attachment(id: UUID(), kind: .audio, relativePath: "audio/user-session.m4a", mediaType: "audio/mp4", byteCount: 24, durationMilliseconds: 900, createdAt: timestamp, isSample: false)
        let appointment = Appointment(id: UUID(), kind: .therapy, scheduledAt: timestamp, startedAt: timestamp, endedAt: nil, providerID: provider.id, providerName: provider.name, recordingAttachmentID: attachment.id, transcriptID: nil, summaryID: nil, status: .recording, manualNotes: "User-owned session")
        let journal = JournalEntry(id: UUID(), createdAt: timestamp, updatedAt: timestamp, inputType: .text, title: "User journal", rawText: "Football is only a shared search word", cleanedText: nil, summaryItems: [], originalAttachmentID: nil, audioAttachmentID: attachment.id, moodLogID: mood.id, pinnedForNextAppointment: false, processingStatus: .unprocessed, provenance: Provenance(voice: .user, label: "You wrote this", detail: "Journal", occurredAt: timestamp, sourceRoute: .journalDetail))
        let goal = Goal(id: UUID(), title: "Keep this goal", detail: "User-owned", cadence: .daily, source: .userExplicit, sourceEntityID: journal.id, sourceTimestampMilliseconds: nil, status: .active, createdAt: timestamp, targetDate: nil, provenance: Provenance(voice: .user, label: "You chose this", detail: "Goal", occurredAt: timestamp, sourceRoute: .goals))
        let progress = GoalProgress(id: UUID(), goalID: goal.id, sourceEntryID: journal.id, note: "Kept progress", source: .userConfirmed, createdAt: timestamp)
        let point = TalkingPoint(id: UUID(), text: "Keep this point", source: .journal, sourceID: journal.id, targetAppointmentKind: .therapy, isImportant: true, status: .open, createdAt: timestamp, provenance: Provenance(voice: .user, label: "You pinned this", detail: "Journal", occurredAt: timestamp, sourceRoute: .journalDetail))
        let artifact = AIArtifact(id: UUID(), kind: .journalSummary, sourceIDs: [journal.id], provider: "local-test", model: "fixed", structuredPayload: Data("{}".utf8), createdAt: timestamp)
        let transcript = TranscriptSegment(id: UUID(), appointmentID: appointment.id, speaker: .patient, rawSpeakerLabel: "Speaker 1", startMilliseconds: 0, endMilliseconds: 1_000, text: "Keep this transcript", confidence: 0.9)
        try await database.write { db in try VaultRecordWriter.save(try ProviderPersistenceRecord(provider), in: db) }
        try await store.saveMood(mood)
        try await store.saveAttachment(attachment)
        try await store.saveAppointment(appointment)
        try await store.saveJournal(journal)
        try await store.saveGoal(goal)
        try await store.addGoalProgress(progress)
        try await store.saveTalkingPoint(point)
        try await store.saveArtifact(artifact)
        try await database.write { db in try VaultRecordWriter.save(try TranscriptPersistenceRecord(transcript, isSample: false), in: db) }
        try await store.setSampleContentEnabled(false)
        let snapshot = try await store.snapshot()
        let searchHits = try await store.search("football", limit: 20)
        #expect(snapshot.providers == [provider])
        #expect(snapshot.moods == [mood])
        #expect(snapshot.attachments == [attachment])
        #expect(snapshot.appointments == [appointment])
        #expect(snapshot.journals == [journal])
        #expect(snapshot.goals == [goal])
        #expect(snapshot.goalProgress == [progress])
        #expect(snapshot.talkingPoints == [point])
        #expect(snapshot.artifacts == [artifact])
        #expect(snapshot.transcript == [transcript])
        #expect(searchHits.map(\.entityID) == [journal.id])
    }

    @Test("Journal deletion removes its search row and corrupt payloads fail safely")
    func deletionAndCorruption() async throws {
        let (root, database, store, _, _) = try VaultTestSupport.make()
        defer { VaultTestSupport.remove(root) }
        _ = try await store.snapshot()
        try await store.deleteJournal(id: SeededData.footballJournalID)
        let remaining = try await store.snapshot()
        let repeated = try await store.snapshot()
        let guiltyHits = try await store.search("guilty", limit: 20)
        #expect(!remaining.journals.contains { $0.id == SeededData.footballJournalID })
        #expect(repeated.journals == remaining.journals)
        #expect(remaining.settings.useSampleContent)
        #expect(!guiltyHits.contains { $0.entityID == SeededData.footballJournalID })

        let corruptID = SeededData.timelineJournalID.uuidString.lowercased()
        try await database.write { db in
            try db.execute(sql: "UPDATE journal_entries SET payload = ? WHERE id = ?", arguments: [Data("not-json".utf8), corruptID])
        }
        var controlled = false
        do { _ = try await store.snapshot() } catch let error as VaultRepositoryError {
            controlled = error == .corruptRecord(table: "journal_entries", id: corruptID)
        }
        #expect(controlled)
    }

    @Test("Journal and search deletion roll back together")
    func deletionIsAtomic() async throws {
        let (root, database, store, _, _) = try VaultTestSupport.make()
        defer { VaultTestSupport.remove(root) }
        _ = try await store.snapshot()
        try await database.write { db in
            try db.execute(sql: "DROP TABLE care_search")
            try db.execute(sql: "CREATE TABLE care_search (kind TEXT, entity_id TEXT, title TEXT, body TEXT, occurred_at REAL)")
            try db.execute(sql: "INSERT INTO care_search VALUES ('journal', ?, '', '', 0)", arguments: [SeededData.footballJournalID.uuidString.lowercased()])
            try db.execute(sql: "CREATE TRIGGER reject_search_delete BEFORE DELETE ON care_search BEGIN SELECT RAISE(ABORT, 'forced rollback'); END")
        }
        var failed = false
        do { try await store.deleteJournal(id: SeededData.footballJournalID) } catch { failed = true }
        let snapshot = try await store.snapshot()
        #expect(failed)
        #expect(snapshot.journals.contains { $0.id == SeededData.footballJournalID })
    }

    private static func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }
}
