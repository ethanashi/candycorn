import Foundation
import Testing
@testable import CandyCorn

@Suite("Journal feature")
@MainActor
struct JournalFeatureTests {
    @Test("Voice timer formatting is deterministic")
    func recordingTimer() {
        #expect(VoiceJournalView.format(milliseconds: 137_000) == "02:17")
        #expect(VoiceJournalView.format(milliseconds: -1) == "00:00")
    }

    @Test("Whitespace cannot save and exact original saves once")
    func originalValidation() {
        var blank = JournalDraftState(text: " \n\t ")
        #expect(blank.beginSave() == nil)

        let exact = "  My exact words.\nSecond line.  "
        var draft = JournalDraftState(text: exact)
        #expect(draft.beginSave() == exact)
        #expect(draft.beginSave() == nil)
        draft.retry()
        #expect(draft.canSave)
    }

    @Test("Repository-backed journal CRUD preserves source and derived fields")
    func journalCRUD() async throws {
        let store = InMemoryCareStore(snapshot: SeededData.careSnapshot)
        let state = DemoState(dependencies: dependencies(store: store))
        await state.load()
        let exact = "  My exact words.\nSecond line.  "
        let created = try #require(await state.createJournal(rawText: exact))
        #expect(created.rawText == exact)
        #expect(created.cleanedText == nil)
        #expect(created.summaryItems.isEmpty)

        let seeded = try #require(state.journals.first { $0.cleanedText != nil })
        let cleaned = seeded.cleanedText
        let summary = seeded.summaryItems
        let attachment = seeded.audioAttachmentID
        #expect(await state.editJournal(id: seeded.id, rawText: "Updated exact source"))
        let edited = try #require(state.journals.first { $0.id == seeded.id })
        #expect(edited.rawText == "Updated exact source")
        #expect(edited.cleanedText == cleaned)
        #expect(edited.summaryItems == summary)
        #expect(edited.audioAttachmentID == attachment)
        #expect(await state.deleteJournal(id: created.id))
        #expect(!state.journals.contains { $0.id == created.id })
    }

    @Test("Denied recording preserves existing journals")
    func deniedRecording() async {
        let store = InMemoryCareStore(snapshot: SeededData.careSnapshot)
        let attachments = InMemoryAttachmentStore()
        let recorder = FakeRecordingService(authorization: .denied, attachments: attachments)
        let state = DemoState(dependencies: dependencies(store: store, attachments: attachments, recorder: recorder))
        let before = state.journals
        #expect(await state.startRecording(kind: .journal) == false)
        #expect(state.journals == before)
    }

    @Test("Interruption finalizes and retains the source attachment")
    func interruptedRecording() async throws {
        let store = InMemoryCareStore(snapshot: SeededData.careSnapshot)
        let state = DemoState(dependencies: dependencies(store: store))
        #expect(await state.startRecording(kind: .journal))
        let recording = try #require(await state.stopRecording(reason: .interruption))
        #expect(await state.stopRecording(reason: .interruption) == nil)
        #expect(recording.stopReason == .interruption)
        #expect(recording.attachment.byteCount > 0)
        #expect(state.attachments.contains { $0.id == recording.attachment.id })
        let entry = await state.createJournal(rawText: "", inputType: .voice, attachmentID: recording.attachment.id)
        #expect(entry?.audioAttachmentID == recording.attachment.id)
        #expect(entry?.cleanedText == nil)
    }

    @Test("Photo source is saved before its journal entry")
    func photoSource() async throws {
        let store = InMemoryCareStore(snapshot: SeededData.emptySnapshot)
        let state = DemoState(dependencies: dependencies(store: store))
        await state.load()
        let attachment = try #require(await state.savePhotoJPEG(Data([0xff, 0xd8, 0xff]), pixelWidth: 12, pixelHeight: 8))
        let entry = try #require(await state.createJournal(rawText: "", inputType: .photo, attachmentID: attachment.id))
        #expect(state.attachments.contains { $0.id == attachment.id })
        #expect(entry.originalAttachmentID == attachment.id)
        #expect(entry.rawText.isEmpty)
        #expect(entry.cleanedText == nil)
        #expect(entry.summaryItems.isEmpty)
    }

    private func dependencies(
        store: InMemoryCareStore,
        attachments: InMemoryAttachmentStore = InMemoryAttachmentStore(),
        recorder: FakeRecordingService? = nil
    ) -> AppDependencies {
        AppDependencies(
            careStore: store, maintenance: store, attachments: attachments,
            recording: recorder ?? FakeRecordingService(attachments: attachments),
            playback: FakeAudioPlaybackService(), photos: FakePhotoAttachmentService(),
            exporter: FakeVaultExporter(store: store, attachments: attachments),
            logger: NoOpEventLogger(), screenshotMode: false,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }
}
