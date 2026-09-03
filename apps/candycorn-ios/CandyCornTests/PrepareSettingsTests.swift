import Testing
@testable import CandyCorn

@Suite("Prepare and Settings")
@MainActor
struct PrepareSettingsTests {
    @Test("Therapy brief has five sourced sections and preserves source records")
    func briefSectionsAndSourcePreservation() {
        let journalsBefore = SeededData.journalEntries
        let transcriptBefore = SeededData.transcript
        var editor = TherapyBriefEditor()

        #expect(TherapyBriefSection.allCases.count == 5)
        #expect(TherapyBriefSection.allCases.allSatisfy { !$0.provenance.label.isEmpty })
        #expect(editor.saved.pinnedQuestion.contains("proof that I could have played"))
        editor.begin()
        editor.update(.possibleOpening, text: "I want to start with the missed opportunity.")
        let didSave = editor.save()
        #expect(didSave)
        #expect(editor.saved.possibleOpening == "I want to start with the missed opportunity.")
        #expect(SeededData.journalEntries == journalsBefore)
        #expect(SeededData.transcript == transcriptBefore)
    }

    @Test("Blank brief copy rejects save and cancel restores the saved version")
    func briefValidationAndCancel() {
        var editor = TherapyBriefEditor()
        let saved = editor.saved

        editor.begin()
        editor.update(.whereLeftOff, text: " \n ")
        let didSave = editor.save()
        #expect(!didSave)
        #expect(editor.error == TherapyBriefEditor.blankMessage)
        #expect(editor.isEditing)
        editor.cancel()
        #expect(!editor.isEditing)
        #expect(editor.draft == saved)
        #expect(editor.saved == saved)
    }

    @Test("Brief fields are bounded without losing saved content")
    func briefLengthBound() {
        var editor = TherapyBriefEditor()
        editor.begin()
        editor.update(.whatChanged, text: String(repeating: "a", count: 900))
        #expect(editor.draft.whatChanged.count == 700)
        #expect(editor.saved == .seeded)
        let didSave = editor.save()
        #expect(didSave)
        #expect(editor.saved.whatChanged.count == 700)
    }

    @Test("AI Off forces provider Off and re-enabling stays Off")
    func aiModeTransitions() {
        let state = DemoState(arguments: ["CandyCorn"])
        #expect(state.aiMode == .organizer)
        #expect(state.aiProvider == .router)

        AISettingsLogic.selectMode(.off, in: state)
        #expect(state.aiMode == .off)
        #expect(state.aiProvider == .off)
        #expect(AISettingsLogic.leavesDeviceCopy(mode: state.aiMode, provider: state.aiProvider) == "Nothing is sent for AI processing.")

        AISettingsLogic.selectMode(.organizer, in: state)
        #expect(state.aiMode == .organizer)
        #expect(state.aiProvider == .off)
        state.setAIProvider(.router)
        AISettingsLogic.selectMode(.reflection, in: state)
        #expect(AISettingsLogic.leavesDeviceCopy(mode: state.aiMode, provider: state.aiProvider).contains("transcript excerpts"))
    }

    @Test("Unavailable router cannot be selected and leaves originals intact")
    func unavailableRouter() {
        let state = DemoState(arguments: ["CandyCorn"])
        let journalsBefore = SeededData.journalEntries
        let transcriptBefore = state.transcript
        state.routerAvailable = false
        state.setAIProvider(.router)

        #expect(!AISettingsLogic.canSelect(.router, in: state))
        #expect(state.aiProvider == .off)
        #expect(state.transcript == transcriptBefore)
        #expect(SeededData.journalEntries == journalsBefore)
        #expect(AISettingsLogic.processingStatus(mode: state.aiMode, provider: state.aiProvider).journal == "Journal intelligence: Off")
    }

    @Test("Retention and export preview remain local")
    func retentionAndExportPreview() {
        var local = SettingsDataInteractionState()
        #expect(local.retention == .ask)
        #expect(!local.showsExportPreview)

        local.selectRetention(.deleteAfterVerification)
        local.toggleExportPreview()
        #expect(local.retention == .deleteAfterVerification)
        #expect(local.showsExportPreview)
        local.toggleExportPreview()
        #expect(!local.showsExportPreview)
    }

    @Test("Reset requires confirmation, supports cancellation, and completes once")
    func resetConfirmation() {
        let state = DemoState(arguments: ["CandyCorn"])
        AISettingsLogic.selectMode(.reflection, in: state)
        var local = SettingsDataInteractionState()

        let resetWithoutConfirmation = local.confirmReset(in: state)
        #expect(!resetWithoutConfirmation)
        #expect(state.aiMode == .reflection)
        local.beginReset()
        local.cancelReset()
        let resetAfterCancel = local.confirmReset(in: state)
        #expect(!resetAfterCancel)
        #expect(state.aiMode == .reflection)

        local.selectRetention(.keep)
        local.toggleExportPreview()
        local.beginReset()
        let firstReset = local.confirmReset(in: state)
        let repeatedReset = local.confirmReset(in: state)
        #expect(firstReset)
        #expect(!repeatedReset)
        #expect(state.aiMode == .organizer)
        #expect(state.aiProvider == .router)
        #expect(local.retention == .ask)
        #expect(!local.showsExportPreview)
        #expect(local.resetComplete)
    }
}
