import Foundation
import Testing
@testable import CandyCorn

@Suite("Continuity features")
@MainActor
struct ContinuityFeatureTests {
    @Test("Goal lifecycle persists provenance and completion once")
    func persistentGoalLifecycle() async throws {
        let state = DemoState()
        let original = try #require(state.goals.first { $0.status == .active })
        let provenance = original.provenance
        #expect(await state.transitionGoal(id: original.id, to: .completed))
        #expect(await state.transitionGoal(id: original.id, to: .completed) == false)
        #expect(state.goalProgress.filter { $0.goalID == original.id && $0.source == .userConfirmed }.count == 1)
        #expect(state.goals.first { $0.id == original.id }?.provenance == provenance)
        #expect(await state.transitionGoal(id: original.id, to: .paused))
        #expect(await state.transitionGoal(id: original.id, to: .active))
        #expect(await state.transitionGoal(id: original.id, to: .dismissed))
    }

    @Test("Talking point lifecycle supports add, discuss, reopen, and dismiss")
    func persistentTalkingPointLifecycle() async throws {
        let state = DemoState()
        let point = try #require(await state.createTalkingPoint(text: "  Ask about the exercise plan  "))
        #expect(point.text == "Ask about the exercise plan")
        #expect(await state.transitionTalkingPoint(id: point.id, to: .discussed))
        #expect(await state.transitionTalkingPoint(id: point.id, to: .open))
        #expect(await state.transitionTalkingPoint(id: point.id, to: .dismissed))
    }

    @Test("Turning off samples keeps user entries")
    func sampleToggle() async throws {
        let state = DemoState()
        let entry = try #require(await state.createJournal(rawText: "My own entry"))
        #expect(await state.setSampleContentEnabled(false))
        #expect(state.journals == [entry])
        #expect(state.goals.isEmpty)
        #expect(await state.setSampleContentEnabled(true))
        #expect(state.journals.contains { $0.id == entry.id })
        #expect(state.journals.count == SeededData.journalEntries.count + 1)
    }

    @Test("Latest search query wins over a slower response")
    func latestQueryWins() async {
        let store = InMemoryCareStore(
            snapshot: SeededData.careSnapshot,
            searchDelays: ["football": .milliseconds(200), "senior": .milliseconds(1)]
        )
        let attachments = InMemoryAttachmentStore()
        let dependencies = AppDependencies(
            careStore: store, maintenance: store, attachments: attachments,
            recording: FakeRecordingService(attachments: attachments), playback: FakeAudioPlaybackService(),
            photos: FakePhotoAttachmentService(), exporter: FakeVaultExporter(store: store, attachments: attachments),
            logger: NoOpEventLogger(), screenshotMode: false, now: { Date() }
        )
        let state = DemoState(dependencies: dependencies)
        let slow = Task { await state.search("football") }
        await Task.yield()
        await state.search("senior")
        await slow.value
        #expect(!state.searchResults.isEmpty)
        #expect(state.searchResults.allSatisfy { $0.title.localizedCaseInsensitiveContains("senior") || $0.excerpt.localizedCaseInsensitiveContains("senior") })
    }
    @Test("Goal cadence order and live counts match the continuity ledger")
    func goalCadences() {
        let sections = GoalLedgerModel.sections(for: SeededData.goals)

        #expect(sections.map(\.cadence) == [.today, .thisWeek, .thisMonth, .ongoing, .homework])
        #expect(sections.map { $0.goals.count } == [1, 1, 0, 1, 1])
        #expect(sections.flatMap(\.goals).allSatisfy { !$0.provenance.label.isEmpty })
        let homework = sections.first { $0.cadence == .homework }?.goals.first
        #expect(homework?.provenance.voice == .provider)
        #expect(homework?.provenance.detail == "Therapy, Sep 2 at 42:18")
    }

    @Test("TMS seeding, manual add, and repeated add are idempotent")
    func talkingPointAdditions() {
        let state = DemoState(arguments: ["CandyCorn"])
        let initialCount = state.talkingPoints.count

        BringUpLogic.ensureTMSPoint(in: state)
        BringUpLogic.ensureTMSPoint(in: state)
        #expect(state.talkingPoints.count == initialCount + 1)
        #expect(state.talkingPoints.filter { $0.id == ContinuityFixtures.tmsTalkingPoint.id }.count == 1)

        var draft = ManualTalkingPointDraft()
        draft.updateText("  Ask whether exercise belongs in the plan  ")
        let point = draft.makeTalkingPoint()
        #expect(point?.text == "Ask whether exercise belongs in the plan")
        #expect(point?.provenance.voice == .user)
        #expect(point.map(state.addTalkingPoint) == true)
        #expect(point.map(state.addTalkingPoint) == false)
        #expect(state.talkingPoints.filter { $0.id == ContinuityFixtures.manualTalkingPointID }.count == 1)
    }

    @Test("Blank manual text is rejected with a concrete error")
    func blankManualPoint() {
        var draft = ManualTalkingPointDraft()
        draft.updateText(" \n\t ")

        #expect(draft.makeTalkingPoint() == nil)
        #expect(draft.error == "Write what you want to bring up first.")
        #expect(draft.text == " \n\t ")
    }

    @Test("Talking points support discussed, dismissed, and all-closed states")
    func talkingPointStatuses() {
        let state = DemoState(arguments: ["CandyCorn"])
        BringUpLogic.ensureTMSPoint(in: state)
        let ids = state.talkingPoints.map(\.id)

        if let first = ids.first {
            state.updateTalkingPoint(id: first, status: .discussed)
        }
        for id in ids.dropFirst() {
            state.updateTalkingPoint(id: id, status: .dismissed)
        }

        #expect(state.talkingPoints.first?.status == .discussed)
        #expect(state.talkingPoints.dropFirst().allSatisfy { $0.status == .dismissed })
        #expect(state.talkingPoints.filter { $0.status == .open }.isEmpty)
    }

    @Test("All five history filters stay local and preserve destinations")
    func historyFilters() {
        let records = HistoryModel.records(mood: SeededData.moodLogs.first)

        #expect(HistoryFilter.allCases == [.all, .journal, .mood, .therapy, .tms])
        #expect(HistoryModel.filteredRecords(records, by: .all).count == 5)
        #expect(HistoryModel.filteredRecords(records, by: .journal).map(\.destination) == [.journalDetail, .journalDetail])
        #expect(HistoryModel.filteredRecords(records, by: .mood).map(\.destination) == [.checkIn])
        #expect(HistoryModel.filteredRecords(records, by: .therapy).map(\.destination) == [.therapySession])
        #expect(HistoryModel.filteredRecords(records, by: .tms).map(\.destination) == [.tmsPost])
        #expect(HistoryModel.filteredRecords(HistoryModel.records(mood: nil), by: .mood).isEmpty)
        #expect(records.map(\.day).contains(.sep5))
        #expect(records.map(\.day).contains(.sep3))
        #expect(records.map(\.day).contains(.sep2))
    }

    @Test("Football search crosses journal, therapy, goals, and talking points")
    func localSearch() {
        let records = MemorySearchModel.records(goals: SeededData.goals, talkingPoints: SeededData.talkingPoints)
        let results = MemorySearchModel.results(for: "  FOOTBALL ", in: records)

        #expect(results.contains { $0.id == "search-journal-football" && $0.destination == .journalDetail })
        #expect(results.contains { $0.id == "search-therapy-football" && $0.destination == .therapySession })
        #expect(results.contains { $0.destination == .goals })
        #expect(results.contains { $0.destination == .bringUp && $0.title.contains("needing proof") })
        #expect(MemorySearchModel.results(for: "watermelon satellite", in: records).isEmpty)
        #expect(MemorySearchModel.results(for: "   ", in: records).isEmpty)
        #expect(MemorySearchModel.boundedQuery(String(repeating: "x", count: 140)).count == 120)
    }
}
