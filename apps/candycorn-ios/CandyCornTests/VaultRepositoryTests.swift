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
        #expect(first.journals == SeededData.journalEntries)
        #expect(second.journals.count == first.journals.count)
        let real = JournalEntry(id: UUID(), createdAt: .now, updatedAt: .now, inputType: .text, title: "A real entry", rawText: "Kept after samples are removed", cleanedText: nil, summaryItems: [], originalAttachmentID: nil, audioAttachmentID: nil, moodLogID: nil, pinnedForNextAppointment: false, processingStatus: .unprocessed, provenance: Provenance(voice: .user, label: "You wrote this", detail: "Journal", occurredAt: .now, sourceRoute: .journalDetail))
        try await store.saveJournal(real)
        try await store.setSampleContentEnabled(false)
        let withoutSamples = try await store.snapshot()
        #expect(withoutSamples.journals == [real])
        #expect(!withoutSamples.settings.useSampleContent)
        try await store.setSampleContentEnabled(true)
        #expect(try await store.snapshot().journals.count == SeededData.journalEntries.count + 1)
    }

    @Test("CRUD persists moods, goals, progress, points, and attachments")
    func crud() async throws {
        let (root, _, store, _, _) = try VaultTestSupport.make()
        defer { VaultTestSupport.remove(root) }
        try await store.setSampleContentEnabled(false)
        let mood = MoodLog(id: UUID(), createdAt: .now, mood: 6, anxiety: 4, energy: 7, customValues: ["focus": 8], note: "Steady")
        try await store.saveMood(mood)
        let goal = Goal(id: UUID(), title: "Walk after lunch", detail: "Ten minutes", cadence: .daily, source: .userExplicit, sourceEntityID: nil, sourceTimestampMilliseconds: nil, status: .active, createdAt: .now, targetDate: nil, provenance: Provenance(voice: .user, label: "You chose this", detail: "Goal", occurredAt: .now, sourceRoute: .goals))
        try await store.saveGoal(goal)
        let progress = GoalProgress(id: UUID(), goalID: goal.id, sourceEntryID: nil, note: "Completed today", source: .userConfirmed, createdAt: .now)
        try await store.addGoalProgress(progress)
        let point = TalkingPoint(id: UUID(), text: "Ask about sleep", source: .manual, sourceID: nil, targetAppointmentKind: .therapy, isImportant: true, status: .open, createdAt: .now, provenance: Provenance(voice: .user, label: "You added this", detail: "Bring up next time", occurredAt: .now, sourceRoute: .bringUp))
        try await store.saveTalkingPoint(point)
        let attachment = Attachment(id: UUID(), kind: .audio, relativePath: "audio/test.m4a", mediaType: "audio/mp4", byteCount: 12, durationMilliseconds: 500, createdAt: .now, isSample: false)
        try await store.saveAttachment(attachment)
        let snapshot = try await store.snapshot()
        #expect(snapshot.moods == [mood])
        #expect(snapshot.goals == [goal])
        #expect(snapshot.goalProgress == [progress])
        #expect(snapshot.talkingPoints == [point])
        #expect(snapshot.attachments == [attachment])
    }

    @Test("Journal deletion removes its search row and corrupt payloads fail safely")
    func deletionAndCorruption() async throws {
        let (root, database, store, _, _) = try VaultTestSupport.make()
        defer { VaultTestSupport.remove(root) }
        _ = try await store.snapshot()
        try await store.deleteJournal(id: SeededData.footballJournalID)
        let remaining = try await store.snapshot()
        let guiltyHits = try await store.search("guilty", limit: 20)
        #expect(!remaining.journals.contains { $0.id == SeededData.footballJournalID })
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
}
