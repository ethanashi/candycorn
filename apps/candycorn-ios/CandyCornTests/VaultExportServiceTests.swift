import Foundation
import Testing
@testable import CandyCorn

@Suite("Care vault export")
struct VaultExportServiceTests {
    @Test("Export preserves sources, relationships, ledgers, and copied attachments")
    func completeExport() async throws {
        let fixture = try ExportFixture(snapshot: exportSnapshot())
        defer { fixture.removeRoot() }
        let package = try await fixture.service.makeExport()

        #expect(package.directoryURL.lastPathComponent.hasPrefix("Candy Corn export 2026-09-02T22-00-00Z"))
        #expect(FileManager.default.fileExists(atPath: package.directoryURL.path))
        let manifest = try decodeManifest(package.directoryURL)
        #expect(manifest.version == ExportManifest.currentVersion)
        #expect(manifest.journals.count == 1)
        #expect(manifest.moods.count == 1)
        #expect(manifest.appointments.count == 1)
        #expect(manifest.goals.count == 1)
        #expect(manifest.goalProgress.count == 1)
        #expect(manifest.talkingPoints.count == 1)
        #expect(manifest.artifacts.count == 1)
        #expect(manifest.attachments.count == 2)
        #expect(manifest.providers.count == 1)
        #expect(manifest.transcripts.count == 1)
        #expect(manifest.artifacts[0].provider == "Local test provider")
        #expect(manifest.artifacts[0].model == "test-model")
        #expect(manifest.artifacts[0].sourceIDs == [ExportIDs.journal])
        #expect(manifest.artifacts[0].structuredPayload == Data([0xff, 0x00, 0x81]))

        let journal = manifest.journals[0]
        #expect(journal.originalAttachmentID == ExportIDs.image)
        #expect(journal.audioAttachmentID == ExportIDs.audio)
        #expect(journal.moodLogID == ExportIDs.mood)
        #expect(journal.attachmentPaths == [
            "attachments/images/\(ExportIDs.image.uuidString.lowercased()).jpg",
            "attachments/audio/\(ExportIDs.audio.uuidString.lowercased()).m4a",
        ])
        let markdown = try String(contentsOf: package.directoryURL.appending(path: journal.markdownPath), encoding: .utf8)
        #expect(markdown.contains("Original line one.\n\nOriginal line three."))
        #expect(markdown.contains("Cleaned text that remains separate."))
        #expect(markdown.contains("A retained summary."))
        #expect(markdown.contains("../attachments/audio/\(ExportIDs.audio.uuidString.lowercased()).m4a"))
        #expect(!journal.markdownPath.contains(".."))
        #expect(journal.markdownPath.count < 140)

        let audioURL = package.directoryURL.appending(path: "attachments/audio/\(ExportIDs.audio.uuidString.lowercased()).m4a")
        let imageURL = package.directoryURL.appending(path: "attachments/images/\(ExportIDs.image.uuidString.lowercased()).jpg")
        #expect(try Data(contentsOf: audioURL) == Data("audio-source".utf8))
        #expect(try Data(contentsOf: imageURL) == Data("image-source".utf8))
        #expect(try String(contentsOf: package.directoryURL.appending(path: "mood.md"), encoding: .utf8).contains("Mood logs"))
        #expect(try String(contentsOf: package.directoryURL.appending(path: "goals.md"), encoding: .utf8).contains("Made progress today"))
        #expect(try String(contentsOf: package.directoryURL.appending(path: "talking-points.md"), encoding: .utf8).contains("Ask about recovery"))
        #expect(try String(contentsOf: package.directoryURL.appending(path: "providers.md"), encoding: .utf8).contains("Dr. Test"))
        #expect(try String(contentsOf: package.directoryURL.appending(path: manifest.appointments[0].markdownPath), encoding: .utf8).contains("Manual appointment notes."))
    }

    @Test("Missing attachments become warnings without exposing vault paths")
    func missingAttachmentWarning() async throws {
        let fixture = try ExportFixture(snapshot: exportSnapshot(), missing: [ExportIDs.audio])
        defer { fixture.removeRoot() }
        let package = try await fixture.service.makeExport()
        let manifest = try decodeManifest(package.directoryURL)
        #expect(manifest.warnings == [ExportWarning(
            code: .attachmentUnavailable,
            attachmentID: ExportIDs.audio,
            message: "The attachment was unavailable and was not copied."
        )])
        #expect(manifest.attachments.first { $0.id == ExportIDs.audio }?.exportPath == nil)
        #expect(manifest.journals[0].attachmentPaths.count == 1)
        let encoded = try String(contentsOf: package.directoryURL.appending(path: "index.json"), encoding: .utf8)
        #expect(!encoded.contains("private-vault"))
        #expect(!encoded.contains("source.m4a"))
    }

    @Test("Empty vault exports complete readable files")
    func emptyExport() async throws {
        let fixture = try ExportFixture(snapshot: makeEmptyExportSnapshot())
        defer { fixture.removeRoot() }
        let package = try await fixture.service.makeExport()
        let manifest = try decodeManifest(package.directoryURL)
        #expect(manifest.journals.isEmpty)
        #expect(manifest.warnings.isEmpty)
        #expect(FileManager.default.fileExists(atPath: package.directoryURL.appending(path: "mood.md").path))
        #expect(FileManager.default.fileExists(atPath: package.directoryURL.appending(path: "goals.md").path))
    }

    @Test("Cleanup is idempotent and rejects packages outside its temporary root")
    func cleanupSafety() async throws {
        let fixture = try ExportFixture(snapshot: makeEmptyExportSnapshot())
        defer { fixture.removeRoot() }
        let package = try await fixture.service.makeExport()
        await fixture.service.cleanup(package)
        #expect(!FileManager.default.fileExists(atPath: package.directoryURL.path))
        await fixture.service.cleanup(package)
        #expect(!FileManager.default.fileExists(atPath: package.directoryURL.path))

        let outside = FileManager.default.temporaryDirectory.appending(path: "outside-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: outside) }
        await fixture.service.cleanup(ExportPackage(directoryURL: outside, createdAt: package.createdAt))
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test("Cancellation removes staging content and publishes no package")
    func cancellationCleanup() async throws {
        let fixture = try ExportFixture(snapshot: exportSnapshot(), copyDelay: .seconds(5))
        defer { fixture.removeRoot() }
        let task = Task { try await fixture.service.makeExport() }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        let children = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path)
        #expect(children.isEmpty)
    }

    private func decodeManifest(_ root: URL) throws -> ExportManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ExportManifest.self, from: Data(contentsOf: root.appending(path: "index.json")))
    }

    private func exportSnapshot() -> CareSnapshot {
        let date = Date(timeIntervalSince1970: 1_788_646_680)
        let provenance = Provenance(voice: .user, label: "You wrote this", detail: "Journal source", occurredAt: date, sourceRoute: .journalDetail)
        let audio = CandyCorn.Attachment(id: ExportIDs.audio, kind: .audio, relativePath: "private-vault/source.m4a", mediaType: "audio/mp4", byteCount: 12, durationMilliseconds: 1_000, createdAt: date, isSample: false)
        let image = CandyCorn.Attachment(id: ExportIDs.image, kind: .image, relativePath: "private-vault/source.jpg", mediaType: "image/jpeg", byteCount: 12, durationMilliseconds: nil, createdAt: date, isSample: false)
        let journal = JournalEntry(
            id: ExportIDs.journal, createdAt: date, updatedAt: date.addingTimeInterval(10), inputType: .photo,
            title: "../../A title: with / hostile * characters and a very long ending that must be bounded 🧠",
            rawText: "Original line one.\n\nOriginal line three.", cleanedText: "Cleaned text that remains separate.",
            summaryItems: ["A retained summary."], originalAttachmentID: ExportIDs.image, audioAttachmentID: ExportIDs.audio,
            moodLogID: ExportIDs.mood, pinnedForNextAppointment: true, processingStatus: .processed, provenance: provenance
        )
        let mood = MoodLog(id: ExportIDs.mood, createdAt: date, mood: 6, anxiety: 4, energy: 7, customValues: ["Focus": 8], note: "Steady | improving")
        var appointment = Appointment(
            id: ExportIDs.appointment, kind: .therapy, scheduledAt: date, startedAt: date,
            endedAt: date.addingTimeInterval(60), providerID: ExportIDs.provider, providerName: "Dr. Test",
            recordingAttachmentID: ExportIDs.audio, transcriptID: ExportIDs.transcript, summaryID: ExportIDs.artifact, status: .completed
        )
        appointment.manualNotes = "Manual appointment notes."
        let goal = Goal(id: ExportIDs.goal, title: "Practice recovery", detail: "One deliberate pause.", cadence: .daily, source: .userExplicit, sourceEntityID: ExportIDs.journal, sourceTimestampMilliseconds: nil, status: .active, createdAt: date, targetDate: date.addingTimeInterval(86_400), provenance: provenance)
        let progress = GoalProgress(id: ExportIDs.progress, goalID: ExportIDs.goal, sourceEntryID: ExportIDs.journal, note: "Made progress today", source: .userConfirmed, createdAt: date)
        let point = TalkingPoint(id: ExportIDs.point, text: "Ask about recovery", source: .journal, sourceID: ExportIDs.journal, targetAppointmentKind: .therapy, isImportant: true, status: .open, createdAt: date, provenance: provenance)
        let artifact = AIArtifact(id: ExportIDs.artifact, kind: .journalSummary, sourceIDs: [ExportIDs.journal], provider: "Local test provider", model: "test-model", structuredPayload: Data([0xff, 0x00, 0x81]), createdAt: date)
        let provider = ProviderProfile(id: ExportIDs.provider, name: "Dr. Test", appointmentKind: .therapy, isSample: false)
        let transcript = TranscriptSegment(id: ExportIDs.transcript, appointmentID: ExportIDs.appointment, speaker: .patient, rawSpeakerLabel: "Speaker 1", startMilliseconds: 0, endMilliseconds: 1_000, text: "Recorded words", confidence: 0.9)
        return CareSnapshot(
            journals: [journal], moods: [mood], appointments: [appointment], goals: [goal], goalProgress: [progress],
            talkingPoints: [point], artifacts: [artifact], attachments: [image, audio], providers: [provider], transcript: [transcript],
            settings: VaultSettings(useSampleContent: false, audioRetention: .keep, aiMode: .off, aiProvider: .off)
        )
    }
}

private enum ExportIDs {
    static let journal = UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!
    static let mood = UUID(uuidString: "A2000000-0000-0000-0000-000000000001")!
    static let appointment = UUID(uuidString: "A3000000-0000-0000-0000-000000000001")!
    static let goal = UUID(uuidString: "A4000000-0000-0000-0000-000000000001")!
    static let progress = UUID(uuidString: "A5000000-0000-0000-0000-000000000001")!
    static let point = UUID(uuidString: "A6000000-0000-0000-0000-000000000001")!
    static let artifact = UUID(uuidString: "A7000000-0000-0000-0000-000000000001")!
    static let audio = UUID(uuidString: "A8000000-0000-0000-0000-000000000001")!
    static let image = UUID(uuidString: "A8000000-0000-0000-0000-000000000002")!
    static let provider = UUID(uuidString: "A9000000-0000-0000-0000-000000000001")!
    static let transcript = UUID(uuidString: "AA000000-0000-0000-0000-000000000001")!
}

private struct ExportFixture {
    let root: URL
    let service: VaultExportService

    init(snapshot: CareSnapshot, missing: Set<UUID> = [], copyDelay: Duration? = nil) throws {
        root = FileManager.default.temporaryDirectory.appending(path: "candycorn-export-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let store = ExportTestCareStore(snapshot: snapshot)
        let attachmentStore = ExportTestAttachmentStore(missing: missing, copyDelay: copyDelay)
        service = VaultExportService(
            store: store, maintenance: store, attachments: attachmentStore, logger: NoOpEventLogger(),
            now: { Date(timeIntervalSince1970: 1_788_386_400) }, temporaryRoot: root
        )
    }

    func removeRoot() { try? FileManager.default.removeItem(at: root) }
}

private actor ExportTestCareStore: CareStore, VaultMaintenance {
    private var current: CareSnapshot

    init(snapshot: CareSnapshot) { current = snapshot }
    func snapshot() -> CareSnapshot { current }
    func saveJournal(_ entry: JournalEntry) { current.journals.append(entry) }
    func deleteJournal(id: UUID) { current.journals.removeAll { $0.id == id } }
    func saveMood(_ mood: MoodLog) { current.moods.append(mood) }
    func saveAppointment(_ appointment: Appointment) { current.appointments.append(appointment) }
    func saveGoal(_ goal: Goal) { current.goals.append(goal) }
    func addGoalProgress(_ progress: GoalProgress) { current.goalProgress.append(progress) }
    func saveTalkingPoint(_ point: TalkingPoint) { current.talkingPoints.append(point) }
    func saveAttachment(_ attachment: CandyCorn.Attachment) { current.attachments.append(attachment) }
    func search(_ query: String, limit: Int) -> [SearchHit] {
        _ = query
        _ = limit
        return []
    }
    func setSampleContentEnabled(_ enabled: Bool) { current.settings.useSampleContent = enabled }
    func updateSettings(_ settings: VaultSettings) { current.settings = settings }
    func destroyAndRecreateVault() { current = makeEmptyExportSnapshot() }
}

private func makeEmptyExportSnapshot() -> CareSnapshot {
    CareSnapshot(
        journals: [], moods: [], appointments: [], goals: [], goalProgress: [], talkingPoints: [],
        artifacts: [], attachments: [], providers: [], transcript: [],
        settings: VaultSettings(useSampleContent: false, audioRetention: .ask, aiMode: .off, aiProvider: .off)
    )
}

private actor ExportTestAttachmentStore: AttachmentStore {
    private let missing: Set<UUID>
    private let copyDelay: Duration?

    init(missing: Set<UUID>, copyDelay: Duration?) {
        self.missing = missing
        self.copyDelay = copyDelay
    }

    func allocateURL(kind: AttachmentKind, fileExtension: String) throws -> URL {
        guard !fileExtension.isEmpty else { throw UserFacingError.saving }
        return FileManager.default.temporaryDirectory.appending(path: kind.rawValue).appendingPathExtension(fileExtension)
    }

    func url(for attachment: CandyCorn.Attachment) -> URL {
        FileManager.default.temporaryDirectory.appending(path: attachment.relativePath)
    }

    func copyIntoExport(_ attachment: CandyCorn.Attachment, destination: URL) async throws {
        if let copyDelay { try await Task.sleep(for: copyDelay) }
        guard !missing.contains(attachment.id) else { throw CocoaError(.fileNoSuchFile) }
        let sourceName = attachment.relativePath.hasSuffix(".jpg") ? "source.jpg" : "source.m4a"
        let data = attachment.kind == .image ? Data("image-source".utf8) : Data("audio-source".utf8)
        try data.write(to: destination.appending(path: sourceName), options: Data.WritingOptions.atomic)
    }

    func removeAll() {}
}
