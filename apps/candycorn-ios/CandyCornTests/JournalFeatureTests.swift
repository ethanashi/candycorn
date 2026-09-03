import Foundation
import Testing
@testable import CandyCorn

@Suite("Journal feature")
@MainActor
struct JournalFeatureTests {
    @Test("Timer formatting and stop state are deterministic")
    func recordingTimer() {
        var recording = JournalRecordingState()
        #expect(recording.elapsedSeconds == 137)
        #expect(JournalRecordingState.format(seconds: recording.elapsedSeconds) == "02:17")
        recording.tick()
        #expect(JournalRecordingState.format(seconds: recording.elapsedSeconds) == "02:18")
        #expect(recording.stop())
        #expect(!recording.stop())
        recording.tick()
        #expect(recording.elapsedSeconds == 138)
        #expect(JournalRecordingState.format(seconds: -1) == "00:00")
    }

    @Test("Whitespace cannot be saved and exact original saves once")
    func originalValidation() {
        var blank = JournalDraftState(text: " \n\t ")
        #expect(!blank.canSave)
        #expect(!blank.saveOriginal())
        #expect(blank.savedOriginal == nil)

        let exact = "  My exact words.\nSecond line.  "
        var draft = JournalDraftState(text: exact)
        #expect(draft.canSave)
        #expect(draft.saveOriginal())
        #expect(draft.savedOriginal == exact)
        draft.text = "A later edit"
        #expect(!draft.saveOriginal())
        #expect(draft.savedOriginal == exact)
    }

    @Test("Rewrite, summary, and photo extraction preserve their sources")
    func sourcePreservation() {
        let source = SeededData.journalEntries.first { $0.id == SeededData.footballJournalID }
        #expect(source != nil)
        let original = source?.rawText

        var draft = JournalDraftState(text: original ?? "Fallback")
        #expect(draft.saveOriginal())
        draft.show(.rewrite)
        #expect(draft.result == .rewrite)
        #expect(draft.savedOriginal == original)
        draft.show(.summary)
        #expect(draft.result == .summary)
        #expect(draft.savedOriginal == original)

        var photo = PhotoJournalState()
        let immutablePage = PhotoJournalState.originalPageText
        photo.capture()
        photo.extractedText = "Corrected extracted words"
        #expect(PhotoJournalState.originalPageText == immutablePage)
        #expect(photo.extractedText == "Corrected extracted words")
        photo.retake()
        #expect(!photo.captured)
        #expect(photo.extractedText == PhotoJournalState.defaultExtraction)
    }

    @Test("Journal suggestions add once and never alter the source")
    func suggestionIdempotence() {
        let state = DemoState()
        let sourceBefore = SeededData.journalEntries.first { $0.id == SeededData.footballJournalID }
        let pointsBefore = state.talkingPoints.count
        let goalsBefore = state.goals.count

        #expect(state.addTalkingPoint(JournalSuggestionFixtures.proofPoint))
        #expect(!state.addTalkingPoint(JournalSuggestionFixtures.proofPoint))
        #expect(state.talkingPoints.count == pointsBefore + 1)
        #expect(state.addGoal(JournalSuggestionFixtures.goal))
        #expect(!state.addGoal(JournalSuggestionFixtures.goal))
        #expect(state.goals.count == goalsBefore + 1)
        #expect(SeededData.journalEntries.first { $0.id == SeededData.footballJournalID } == sourceBefore)
    }

    @Test("AI unavailability leaves state and source untouched")
    func unavailableStates() {
        let state = DemoState()
        let sourceBefore = SeededData.journalEntries
        let pointsBefore = state.talkingPoints
        let goalsBefore = state.goals

        state.setAIMode(.off)
        state.routerAvailable = false
        #expect(state.aiMode == .off)
        #expect(state.aiProvider == .off)
        #expect(state.talkingPoints == pointsBefore)
        #expect(state.goals == goalsBefore)
        #expect(SeededData.journalEntries == sourceBefore)
    }
}
