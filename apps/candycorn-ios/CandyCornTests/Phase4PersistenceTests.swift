import Foundation
import GRDB
import Testing
@testable import CandyCorn

@Suite("Phase 4 persistence")
struct Phase4PersistenceTests {
    @Test("Screenshot dependencies use deterministic Phase 4 adapters")
    func screenshotDependenciesAreLocalFakes() async throws {
        let dependencies = PreviewDependencies.make(screenshotMode: true)
        #expect(dependencies.transcriber is FakeTranscriber)
        #expect(dependencies.diarizer is FakeDiarizer)
        #expect(dependencies.sessionSummarizer is FakeSessionSummarizer)
        #expect(dependencies.sessionProcessing is FakeSessionProcessing)

        let source = SessionTranscriptSource(
            id: UUID(), speaker: .patient, rawSpeakerLabel: "speaker-a",
            startMilliseconds: 100, endMilliseconds: 900,
            text: "I felt calmer after the session."
        )
        let input = StructuredSessionSummaryInput(
            appointmentID: UUID(), template: .tms, transcript: [source], openTalkingPoints: []
        )
        let result = try await dependencies.sessionSummarizer.summarizeSession(input)
        #expect(result.template == .tms)
        #expect(result.debriefTopics.count == 3)
        #expect(result.sections.first?.kind == .providerInstructions)
    }

    @Test("A v3 vault migrates without changing existing payloads")
    func migrationPreservesExistingData() throws {
        let root = Self.temporaryRoot("migration")
        defer { VaultTestSupport.remove(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let queue = try VaultTestSupport.rawQueue(
            url: root.appending(path: "care.db"),
            key: Data(repeating: 0x44, count: 32)
        )
        let migrator = VaultMigrations.makeMigrator()
        try migrator.migrate(queue, upTo: "v3_search")
        let journal = Self.journal()
        let settings = VaultSettings(useSampleContent: false, audioRetention: .keep, aiMode: .off, aiProvider: .off)
        try queue.write { db in
            try VaultRecordWriter.save(try JournalPersistenceRecord(journal, isSample: false), in: db)
            try VaultRecordWriter.saveSettings(settings, in: db)
        }

        try migrator.migrate(queue)

        let result = try queue.read { db -> (JournalEntry, VaultSettings, [String], [String]) in
            guard let journalPayload = try Data.fetchOne(db, sql: "SELECT payload FROM journal_entries WHERE id = ?", arguments: [journal.id.uuidString.lowercased()]),
                  let settingsPayload = try Data.fetchOne(db, sql: "SELECT payload FROM app_settings WHERE id = 1") else {
                throw VaultRepositoryError.databaseUnavailable
            }
            let migrations = try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid")
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
            return (
                try PersistenceCoding.decode(JournalEntry.self, from: journalPayload, table: "journal_entries", id: journal.id.uuidString),
                try PersistenceCoding.decode(VaultSettings.self, from: settingsPayload, table: "app_settings", id: "1"),
                migrations,
                tables
            )
        }
        #expect(result.0 == journal)
        #expect(result.1 == settings)
        #expect(result.2 == ["v1_core", "v2_relations", "v3_search", "v4_appointment_audio"])
        for table in Self.phase4Tables {
            #expect(result.3.contains(table))
        }
    }

    @Test("Transcript replacement validates first and refreshes transcript search")
    func transcriptReplacementIsAtomicAndSearchable() async throws {
        let fixture = try await makeFixture("transcript")
        defer { VaultTestSupport.remove(fixture.root) }
        let original = Self.segment(fixture.appointment.id, id: UUID(), label: "speaker-a", start: 0, end: 800, text: "Original words")
        try await fixture.store.replaceTranscriptSegments([original], for: fixture.appointment.id)

        let invalid = Self.segment(fixture.appointment.id, id: UUID(), label: "speaker-a", start: 900, end: 900, text: "Invalid range")
        var invalidRejected = false
        do { try await fixture.store.replaceTranscriptSegments([invalid], for: fixture.appointment.id) } catch { invalidRejected = true }
        let afterInvalid = try await fixture.store.snapshot()
        #expect(invalidRejected)
        #expect(afterInvalid.transcript == [original])

        let otherAppointment = Self.appointment(id: UUID())
        try await fixture.store.saveAppointment(otherAppointment)
        let mixed = Self.segment(otherAppointment.id, id: UUID(), label: "speaker-b", start: 1_000, end: 2_000, text: "Other appointment")
        var mixedRejected = false
        do { try await fixture.store.replaceTranscriptSegments([original, mixed], for: fixture.appointment.id) } catch { mixedRejected = true }
        let afterMixed = try await fixture.store.snapshot()
        #expect(mixedRejected)
        #expect(afterMixed.transcript == [original])

        let replacement = Self.segment(fixture.appointment.id, id: UUID(), label: "speaker-a", start: 2_000, end: 3_000, text: "Relief brought unexpected guilt")
        try await fixture.store.replaceTranscriptSegments([replacement], for: fixture.appointment.id)
        let hits = try await fixture.store.search("unexpected guilt", limit: 10)
        #expect(hits.count == 1)
        #expect(hits.first?.kind == .transcript)
        #expect(hits.first?.entityID == fixture.appointment.id)
    }

    @Test("Cluster correction relabels its cluster and remembers only the patient voice")
    func clusterCorrectionPersists() async throws {
        let fixture = try await makeFixture("cluster")
        defer { VaultTestSupport.remove(fixture.root) }
        let matchingA = Self.segment(fixture.appointment.id, id: UUID(), label: "speaker-a", start: 0, end: 900, text: "First patient line")
        let other = Self.segment(fixture.appointment.id, id: UUID(), label: "speaker-b", start: 1_000, end: 1_900, text: "Provider line")
        let matchingB = Self.segment(fixture.appointment.id, id: UUID(), label: "speaker-a", start: 2_000, end: 2_900, text: "Second patient line")
        try await fixture.store.replaceTranscriptSegments([matchingA, other, matchingB], for: fixture.appointment.id)
        let embedding = SpeakerEmbedding(rawSpeakerLabel: "speaker-a", modelID: "fluid-test", values: [0.1, 0.2, 0.3])
        try await fixture.store.saveSpeakerEmbeddings([embedding], for: fixture.appointment.id)
        let assignment = SpeakerClusterAssignment(
            id: UUID(), appointmentID: fixture.appointment.id, rawSpeakerLabel: "speaker-a",
            speaker: .patient, updatedAt: Self.timestamp
        )
        try await fixture.store.assignSpeakerCluster(assignment, rememberPatientVoice: true)

        let reopened = VaultRepositories(database: fixture.database, logger: NoOpEventLogger())
        let snapshot = try await reopened.snapshot()
        let corrected = snapshot.transcript.filter { $0.rawSpeakerLabel == "speaker-a" }
        #expect(corrected.count == 2)
        #expect(corrected.allSatisfy { $0.speaker == .patient })
        #expect(snapshot.transcript.first { $0.rawSpeakerLabel == "speaker-b" }?.speaker == .unknown)
        #expect(snapshot.speakerAssignments == [assignment])
        #expect(snapshot.speakerEmbeddings == [embedding])
        #expect(snapshot.patientVoiceProfiles.count == 1)
        #expect(snapshot.patientVoiceProfiles.first?.embedding == embedding.values)
        #expect(snapshot.artifacts.isEmpty)

        let provider = SpeakerClusterAssignment(
            id: UUID(), appointmentID: fixture.appointment.id, rawSpeakerLabel: "speaker-b",
            speaker: .provider, updatedAt: Self.timestamp
        )
        var providerProfileRejected = false
        do { try await reopened.assignSpeakerCluster(provider, rememberPatientVoice: true) } catch { providerProfileRejected = true }
        let afterProviderAttempt = try await reopened.snapshot()
        #expect(providerProfileRejected)
        #expect(afterProviderAttempt.patientVoiceProfiles.count == 1)
    }

    @Test("Debrief decisions and their targets are idempotent")
    func debriefMutationIsIdempotent() async throws {
        let fixture = try await makeFixture("debrief")
        defer { VaultTestSupport.remove(fixture.root) }
        let goal = Goal(
            id: UUID(), title: "Notice when relief brings guilt", detail: nil, cadence: .homework,
            source: .providerExplicit, sourceEntityID: fixture.appointment.id,
            sourceTimestampMilliseconds: 3_200, status: .active, createdAt: Self.timestamp,
            targetDate: nil, provenance: Self.provenance(.provider)
        )
        let decision = SessionDebriefDecision(
            id: UUID(), appointmentID: fixture.appointment.id, summaryItemID: UUID(),
            kind: .addedHomework, targetEntityID: goal.id, editedText: nil, createdAt: Self.timestamp
        )
        let mutation = SessionDebriefMutation.addGoal(decision: decision, goal: goal)
        try await fixture.store.applySessionDebriefMutation(mutation)
        try await fixture.store.applySessionDebriefMutation(mutation)
        let snapshot = try await fixture.store.snapshot()
        #expect(snapshot.debriefDecisions == [decision])
        #expect(snapshot.goals == [goal])

        let mismatch = SessionDebriefDecision(
            id: UUID(), appointmentID: fixture.appointment.id, summaryItemID: UUID(),
            kind: .addedGoal, targetEntityID: UUID(), editedText: nil, createdAt: Self.timestamp
        )
        var mismatchRejected = false
        do { try await fixture.store.applySessionDebriefMutation(.addGoal(decision: mismatch, goal: goal)) } catch { mismatchRejected = true }
        let afterMismatch = try await fixture.store.snapshot()
        #expect(mismatchRejected)
        #expect(afterMismatch.debriefDecisions == [decision])
    }

    @Test("Appointment deletion cascades through every appointment audio table")
    func appointmentCascadeRemovesPhase4Rows() async throws {
        let fixture = try await makeFixture("cascade")
        defer { VaultTestSupport.remove(fixture.root) }
        let segment = Self.segment(fixture.appointment.id, id: UUID(), label: "speaker-a", start: 0, end: 1_000, text: "Saved transcript")
        try await fixture.store.replaceTranscriptSegments([segment], for: fixture.appointment.id)
        try await fixture.store.saveSpeakerEmbeddings(
            [SpeakerEmbedding(rawSpeakerLabel: "speaker-a", modelID: "fluid-test", values: [0.2, 0.4])],
            for: fixture.appointment.id
        )
        let assignment = SpeakerClusterAssignment(
            id: UUID(), appointmentID: fixture.appointment.id, rawSpeakerLabel: "speaker-a",
            speaker: .patient, updatedAt: Self.timestamp
        )
        try await fixture.store.assignSpeakerCluster(assignment, rememberPatientVoice: true)
        let processing = SessionProcessingRecord(
            id: UUID(), appointmentID: fixture.appointment.id, stage: .summarizing, progress: 0.75,
            summaryConsentGranted: false,
            failure: SessionProcessingFailure(code: .summaryPermissionRequired, message: "Review what leaves this device."),
            updatedAt: Self.timestamp
        )
        try await fixture.store.saveSessionProcessing(processing)
        let decision = SessionDebriefDecision(
            id: UUID(), appointmentID: fixture.appointment.id, summaryItemID: UUID(),
            kind: .ignoredGoal, targetEntityID: nil, editedText: nil, createdAt: Self.timestamp
        )
        try await fixture.store.applySessionDebriefMutation(.ignoreGoal(decision: decision))

        try await fixture.database.write { db in
            try db.execute(sql: "DELETE FROM appointments WHERE id = ?", arguments: [fixture.appointment.id.uuidString.lowercased()])
        }
        let snapshot = try await fixture.store.snapshot()
        #expect(snapshot.transcript.isEmpty)
        #expect(snapshot.sessionProcessing.isEmpty)
        #expect(snapshot.speakerAssignments.isEmpty)
        #expect(snapshot.speakerEmbeddings.isEmpty)
        #expect(snapshot.patientVoiceProfiles.isEmpty)
        #expect(snapshot.debriefDecisions.isEmpty)
    }

    private static let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
    private static let phase4Tables = [
        "session_processing", "speaker_cluster_assignments", "speaker_embeddings",
        "patient_voice_profiles", "session_debrief_decisions",
    ]

    private static func temporaryRoot(_ suffix: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "candycorn-phase4-\(suffix)-\(UUID().uuidString)")
    }

    private func makeFixture(_ suffix: String) async throws -> Phase4Fixture {
        let (root, database, store, _, _) = try VaultTestSupport.make(name: "phase4-\(suffix)-\(UUID().uuidString)")
        try await store.setSampleContentEnabled(false)
        let appointment = Self.appointment(id: UUID())
        try await store.saveAppointment(appointment)
        return Phase4Fixture(root: root, database: database, store: store, appointment: appointment)
    }

    private static func appointment(id: UUID) -> Appointment {
        Appointment(
            id: id, kind: .therapy, scheduledAt: timestamp, startedAt: timestamp,
            endedAt: timestamp.addingTimeInterval(3_600), providerID: nil,
            providerName: "Dr. Morgan", recordingAttachmentID: nil, transcriptID: nil,
            summaryID: nil, status: .processing
        )
    }

    private static func segment(
        _ appointmentID: UUID,
        id: UUID,
        label: String,
        start: Int,
        end: Int,
        text: String
    ) -> TranscriptSegment {
        TranscriptSegment(
            id: id, appointmentID: appointmentID, speaker: .unknown, rawSpeakerLabel: label,
            startMilliseconds: start, endMilliseconds: end, text: text, confidence: 0.9
        )
    }

    private static func journal() -> JournalEntry {
        JournalEntry(
            id: UUID(), createdAt: timestamp, updatedAt: timestamp, inputType: .text,
            title: "Migration check", rawText: "Preserve this entry", cleanedText: nil,
            summaryItems: [], originalAttachmentID: nil, audioAttachmentID: nil,
            moodLogID: nil, pinnedForNextAppointment: false, processingStatus: .unprocessed,
            provenance: provenance(.user)
        )
    }

    private static func provenance(_ voice: ProvenanceVoice) -> Provenance {
        Provenance(
            voice: voice, label: "Test provenance", detail: "Fictional fixture",
            occurredAt: timestamp, sourceRoute: nil
        )
    }
}

private struct Phase4Fixture {
    let root: URL
    let database: VaultDatabase
    let store: VaultRepositories
    let appointment: Appointment
}
