import Foundation
import Testing
@testable import CandyCorn

@Suite("Arrival and Today")
@MainActor
struct ArrivalTodayTests {
    @Test("Welcome stays within four pages and completes only at the end")
    func welcomeBounds() {
        var flow = WelcomeFlowState()
        #expect(WelcomeView.pages.count == WelcomeFlowState.pageCount)
        flow.goBack()
        #expect(flow.pageIndex == 0)
        #expect(flow.advance() == false)
        #expect(flow.pageIndex == 1)
        #expect(flow.advance() == false)
        #expect(flow.advance() == false)
        #expect(flow.pageIndex == 3)
        #expect(flow.advance() == true)
        #expect(flow.pageIndex == 3)
        flow.goBack()
        #expect(flow.pageIndex == 2)
    }

    @Test("Welcome completion opens Today")
    func welcomeCompletion() {
        let navigation = NavigationModel(arguments: ["CandyCorn"])
        #expect(!navigation.onboardingComplete)
        navigation.completeOnboarding()
        #expect(navigation.onboardingComplete)
        #expect(navigation.selectedTab == .today)
        #expect(navigation.presentedFlow == nil)
    }

    @Test("Check-in draft sets absolute values and caps notes")
    func checkInDraftEditing() {
        let now = Date(timeIntervalSince1970: 20)
        let source = MoodLog(id: UUID(), createdAt: Date(timeIntervalSince1970: 1), mood: 10, anxiety: nil, energy: 4, customValues: ["focus": 7], note: nil)
        var draft = CheckInDraft(mood: source, now: now)
        draft.set(.mood, to: nil)
        draft.set(.anxiety, to: 8)
        draft.set(.energy, to: 5)
        draft.updateNote(String(repeating: "x", count: 181))
        #expect(draft.values.mood == nil)
        #expect(draft.values.anxiety == 8)
        #expect(draft.values.energy == 5)
        #expect(draft.note.count == 180)
        #expect(draft.beginSave()?.customValues == ["focus": 7])
    }

    @Test("Cancel leaves shared mood unchanged")
    func checkInCancel() {
        let state = DemoState()
        let original = state.mood
        var draft = CheckInDraft(mood: state.mood, now: state.dependencies.now())
        draft.set(.mood, to: 9)
        draft.updateNote("Changed only in the draft")
        #expect(state.mood == original)
        #expect(draft.values.mood != original?.mood)
    }

    @Test("Save produces one normalized mood even under rapid activation")
    func checkInSaveOnce() {
        let state = DemoState()
        var draft = CheckInDraft(mood: state.mood, now: state.dependencies.now())
        draft.set(.anxiety, to: 8)
        draft.updateNote("  A short note  ")
        let first = draft.beginSave()
        let second = draft.beginSave()
        #expect(first?.anxiety == 8)
        #expect(first?.note == "A short note")
        #expect(second == nil)
        state.saveMood(first)
        #expect(state.mood?.anxiety == 8)
        #expect(state.mood?.note == "A short note")
    }

    @Test("Empty check-in retains not-logged values and an empty optional note")
    func emptyCheckIn() {
        let now = Date(timeIntervalSince1970: 42)
        var draft = CheckInDraft(mood: nil, now: now)
        #expect(draft.values == MoodValues(mood: nil, anxiety: nil, energy: nil))
        #expect(draft.note.isEmpty)
        let saved = draft.beginSave()
        #expect(saved?.mood == nil)
        #expect(saved?.anxiety == nil)
        #expect(saved?.energy == nil)
        #expect(saved?.note == nil)
        #expect(saved?.createdAt == now)
    }

    @Test("Mood adjustments can clear a logged dimension")
    func moodAdjustmentClearsDimension() {
        let logged: Int? = 1
        let notLogged: Int? = nil
        #expect(MoodBandSelection.adjusted(logged, by: -1) == nil)
        #expect(MoodBandSelection.adjusted(notLogged, by: -1) == 4)
        #expect(MoodBandSelection.adjusted(notLogged, by: 1) == 6)
    }
}
