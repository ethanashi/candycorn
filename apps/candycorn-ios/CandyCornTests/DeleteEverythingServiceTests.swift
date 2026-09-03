import Foundation
import Testing
@testable import CandyCorn

@Suite("Delete everything service")
struct DeleteEverythingServiceTests {
    @Test("Confirmation requires the exact typed value")
    func exactConfirmation() {
        #expect(DeleteConfirmation(typedText: "DELETE")?.accepted == true)
        #expect(DeleteConfirmation(typedText: "delete") == nil)
        #expect(DeleteConfirmation(typedText: " DELETE") == nil)
        #expect(DeleteConfirmation(typedText: "DELETE ") == nil)
    }

    @Test("Reset waits for a usable replacement and repeated activation is idempotent")
    func successfulResetOrdering() async throws {
        let maintenance = ExportTestMaintenance()
        let service = makeService(maintenance: maintenance)
        let confirmation = try #require(DeleteConfirmation(typedText: "DELETE"))
        try await service.deleteEverything(confirmation: confirmation)
        #expect(await maintenance.callCount == 1)
        #expect(await maintenance.replacementUsable)
        try await service.deleteEverything(confirmation: confirmation)
        #expect(await maintenance.callCount == 1)
    }

    @Test("A failed reset reports a safe failure and permits retry")
    func failureAndRetry() async throws {
        let maintenance = ExportTestMaintenance(failuresRemaining: 1)
        let service = makeService(maintenance: maintenance)
        let confirmation = try #require(DeleteConfirmation(typedText: "DELETE"))
        await #expect(throws: UserFacingError(message: "Your care vault could not be deleted. Try again.")) {
            try await service.deleteEverything(confirmation: confirmation)
        }
        #expect(await maintenance.callCount == 1)
        #expect(!(await maintenance.replacementUsable))
        try await service.deleteEverything(confirmation: confirmation)
        #expect(await maintenance.callCount == 2)
        #expect(await maintenance.replacementUsable)
    }

    private func makeService(maintenance: ExportTestMaintenance) -> VaultExportService {
        let store = ExportDeleteCareStore()
        return VaultExportService(
            store: store, maintenance: maintenance, attachments: ExportDeleteAttachmentStore(),
            logger: NoOpEventLogger(), now: { Date(timeIntervalSince1970: 1_788_386_400) }
        )
    }
}

private actor ExportDeleteCareStore: CareStore {
    func snapshot() -> CareSnapshot {
        CareSnapshot(
            journals: [], moods: [], appointments: [], goals: [], goalProgress: [], talkingPoints: [],
            artifacts: [], attachments: [], providers: [], transcript: [],
            settings: VaultSettings(useSampleContent: false, audioRetention: .ask, aiMode: .off, aiProvider: .off)
        )
    }
    func saveJournal(_ entry: JournalEntry) { _ = entry }
    func deleteJournal(id: UUID) { _ = id }
    func saveMood(_ mood: MoodLog) { _ = mood }
    func saveAppointment(_ appointment: Appointment) { _ = appointment }
    func saveGoal(_ goal: Goal) { _ = goal }
    func addGoalProgress(_ progress: GoalProgress) { _ = progress }
    func saveTalkingPoint(_ point: TalkingPoint) { _ = point }
    func saveAttachment(_ attachment: CandyCorn.Attachment) { _ = attachment }
    func search(_ query: String, limit: Int) -> [SearchHit] {
        _ = query
        _ = limit
        return []
    }
    func setSampleContentEnabled(_ enabled: Bool) { _ = enabled }
    func updateSettings(_ settings: VaultSettings) { _ = settings }
}

private actor ExportTestMaintenance: VaultMaintenance {
    private(set) var callCount = 0
    private(set) var replacementUsable = false
    private var failuresRemaining: Int

    init(failuresRemaining: Int = 0) {
        self.failuresRemaining = failuresRemaining
    }

    func destroyAndRecreateVault() async throws {
        callCount += 1
        replacementUsable = false
        try await Task.sleep(for: .milliseconds(10))
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw ExportTestResetError.expected
        }
        replacementUsable = true
    }
}

private enum ExportTestResetError: Error {
    case expected
}

private actor ExportDeleteAttachmentStore: AttachmentStore {
    func allocateURL(kind: AttachmentKind, fileExtension: String) throws -> URL {
        guard !fileExtension.isEmpty else { throw UserFacingError.saving }
        return FileManager.default.temporaryDirectory.appending(path: kind.rawValue).appendingPathExtension(fileExtension)
    }

    func url(for attachment: CandyCorn.Attachment) -> URL {
        FileManager.default.temporaryDirectory.appending(path: attachment.relativePath)
    }

    func copyIntoExport(_ attachment: CandyCorn.Attachment, destination: URL) {
        _ = attachment
        _ = destination
    }

    func removeAll() {}
}
