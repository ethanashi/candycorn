import Foundation
import Testing
@testable import CandyCorn

@Suite("Demo state")
@MainActor
struct DemoStateTests {
    @Test("Mood saves, clears, clamps, and resets")
    func moodTransitions() {
        let state = DemoState()
        let custom = MoodLog(id: UUID(), createdAt: Date(timeIntervalSince1970: 1), mood: 12, anxiety: 0, energy: nil, customValues: ["focus": 99], note: "A fictional note")
        state.saveMood(custom)
        #expect(state.mood?.mood == 10)
        #expect(state.mood?.anxiety == 1)
        #expect(state.mood?.energy == nil)
        #expect(state.mood?.customValues["focus"] == 10)
        state.saveMood(nil)
        #expect(state.mood == nil)
        state.reset()
        #expect(state.mood == SeededData.moodLogs.first)
    }

    @Test("Goal additions and completion are idempotent")
    func goalTransitions() {
        let state = DemoState()
        let goal = SeededData.goals[0]
        #expect(state.addGoal(goal) == false)
        let count = state.goals.count
        state.toggleGoal(id: goal.id)
        #expect(state.goals.first { $0.id == goal.id }?.status == .completed)
        state.toggleGoal(id: goal.id)
        #expect(state.goals.first { $0.id == goal.id }?.status == .active)
        #expect(state.goals.count == count)
    }

    @Test("Talking point additions and updates are deterministic")
    func talkingPointTransitions() {
        let state = DemoState()
        let point = SeededData.talkingPoints[0]
        #expect(state.addTalkingPoint(point) == false)
        state.updateTalkingPoint(id: point.id, status: .discussed)
        #expect(state.talkingPoints.first { $0.id == point.id }?.status == .discussed)
        #expect(state.talkingPoints.count == SeededData.talkingPoints.count)
    }

    @Test("AI mode and provider rules stay consistent")
    func aiTransitions() {
        let state = DemoState()
        state.setAIMode(.off)
        #expect(state.aiMode == .off)
        #expect(state.aiProvider == .off)
        state.setAIProvider(.router)
        #expect(state.aiProvider == .off)
        state.routerAvailable = false
        state.setAIMode(.reflection)
        #expect(state.aiProvider == .off)
        state.setAIProvider(.router)
        #expect(state.aiProvider == .off)
        state.routerAvailable = true
        state.setAIMode(.organizer)
        #expect(state.aiProvider == .off)
        state.setAIProvider(.router)
        #expect(state.aiProvider == .router)
        state.setAIMode(.reflection)
        #expect(state.aiProvider == .router)
        state.setAIMode(.off)
        #expect(state.aiProvider == .off)
    }

    @Test("Mood persistence refreshes the repository and selects the saved record")
    func moodPersistenceRefreshesSnapshot() async {
        var snapshot = SeededData.careSnapshot
        let future = MoodLog(
            id: UUID(), createdAt: Date(timeIntervalSince1970: 9_999),
            mood: 2, anxiety: 3, energy: 4, customValues: [:], note: nil
        )
        snapshot.moods = [future]
        let store = MoodTestCareStore(snapshot: snapshot, clearsGoalsAfterMoodSave: true)
        let state = DemoState(dependencies: makeDependencies(careStore: store), arguments: ["CandyCorn"])
        await state.load()
        let saved = MoodLog(
            id: UUID(), createdAt: Date(timeIntervalSince1970: 10),
            mood: 12, anxiety: 0, energy: nil, customValues: ["focus": 99], note: "Steady"
        )

        #expect(await state.persistMood(saved))
        #expect(await store.moodSaveCount == 1)
        #expect(state.mood == saved.normalized())
        #expect(state.goals.isEmpty)
    }

    @Test("Failed mood persistence preserves state and can be retried")
    func moodPersistenceFailure() async {
        let store = MoodTestCareStore(snapshot: SeededData.careSnapshot, failsMoodSave: true)
        let state = DemoState(dependencies: makeDependencies(careStore: store), arguments: ["CandyCorn"])
        await state.load()
        let priorMood = state.mood
        let saved = MoodLog(
            id: UUID(), createdAt: Date(timeIntervalSince1970: 10),
            mood: 8, anxiety: nil, energy: 6, customValues: ["focus": 5], note: nil
        )

        #expect(await state.persistMood(saved) == false)
        #expect(state.mood == priorMood)
        #expect(state.operationError == UserFacingError.saving.message)
        await store.setFailsMoodSave(false)
        #expect(await state.persistMood(saved))
        #expect(state.mood == saved)
    }

    @Test("Consent gates recording and duplicate activation")
    func recordingTransitions() {
        let state = DemoState(arguments: ["CandyCorn"])
        #expect(state.startAppointmentRecording() == false)
        state.consentAcknowledged = true
        #expect(state.startAppointmentRecording() == true)
        #expect(state.startAppointmentRecording() == false)
        #expect(state.finishAppointmentRecording(durationSeconds: 138) == true)
        #expect(state.finishAppointmentRecording(durationSeconds: 139) == false)
        #expect(state.appointmentRecording == .saved(durationSeconds: 138))
        state.selectAppointmentKind(.tms)
        #expect(state.consentAcknowledged == false)
        #expect(state.appointmentRecording == .idle)
    }

    @Test("Active appointment screenshot launch is prepared")
    func activeAppointmentLaunch() {
        let state = DemoState(arguments: ["CandyCorn", "-screen", "/appointments/active"])
        #expect(state.consentAcknowledged)
        #expect(state.appointmentRecording == .recording(startSeconds: 0))
        state.reset()
        #expect(!state.consentAcknowledged)
        #expect(state.appointmentRecording == .idle)
    }

    @Test("Only unknown speakers can be corrected without changing source text")
    func speakerCorrection() {
        let state = DemoState()
        let known = state.transcript.first { $0.speaker == .patient }!
        let unknown = state.transcript.first { $0.speaker == .unknown }!
        let original = state.transcript
        #expect(state.correctSpeaker(segmentID: known.id, to: .provider) == false)
        #expect(state.correctSpeaker(segmentID: unknown.id, to: .patient) == true)
        #expect(state.correctSpeaker(segmentID: unknown.id, to: .provider) == false)
        #expect(state.correctSpeaker(segmentID: unknown.id, to: .unknown) == false)
        #expect(state.transcript == original)
        #expect(state.speakerCorrections[unknown.id] == .patient)
        state.reset()
        #expect(state.speakerCorrections.isEmpty)
        #expect(state.goals == SeededData.goals)
        #expect(state.talkingPoints == SeededData.talkingPoints)
    }

    private func makeDependencies(careStore: any CareStore) -> AppDependencies {
        let base = PreviewDependencies.make()
        return AppDependencies(
            careStore: careStore,
            maintenance: base.maintenance,
            attachments: base.attachments,
            recording: base.recording,
            playback: base.playback,
            photos: base.photos,
            exporter: base.exporter,
            logger: base.logger,
            languageModel: base.languageModel,
            visionReader: base.visionReader,
            transcriber: base.transcriber,
            distressClassifier: base.distressClassifier,
            openRouterKeyStore: base.openRouterKeyStore,
            aiConfigurationStore: base.aiConfigurationStore,
            screenshotMode: false,
            now: base.now
        )
    }
}

private actor MoodTestCareStore: CareStore {
    private var current: CareSnapshot
    private var failsMoodSave: Bool
    private let clearsGoalsAfterMoodSave: Bool
    private(set) var moodSaveCount = 0

    init(
        snapshot: CareSnapshot,
        failsMoodSave: Bool = false,
        clearsGoalsAfterMoodSave: Bool = false
    ) {
        current = snapshot
        self.failsMoodSave = failsMoodSave
        self.clearsGoalsAfterMoodSave = clearsGoalsAfterMoodSave
    }

    func snapshot() -> CareSnapshot { current }

    func saveMood(_ mood: MoodLog) throws {
        guard !failsMoodSave else { throw UserFacingError.saving }
        moodSaveCount += 1
        if let index = current.moods.firstIndex(where: { $0.id == mood.id }) {
            current.moods[index] = mood.normalized()
        } else {
            current.moods.append(mood.normalized())
        }
        if clearsGoalsAfterMoodSave {
            current.goals = []
        }
    }

    func setFailsMoodSave(_ fails: Bool) { failsMoodSave = fails }
    func saveJournal(_ entry: JournalEntry) { _ = entry }
    func deleteJournal(id: UUID) { _ = id }
    func saveAppointment(_ appointment: Appointment) { _ = appointment }
    func saveGoal(_ goal: Goal) { _ = goal }
    func addGoalProgress(_ progress: GoalProgress) { _ = progress }
    func saveTalkingPoint(_ point: TalkingPoint) { _ = point }
    func saveAttachment(_ attachment: CandyCorn.Attachment) { _ = attachment }
    func search(_ query: String, limit: Int) -> [SearchHit] { [] }
    func setSampleContentEnabled(_ enabled: Bool) { _ = enabled }
    func updateSettings(_ settings: VaultSettings) { current.settings = settings }
}
