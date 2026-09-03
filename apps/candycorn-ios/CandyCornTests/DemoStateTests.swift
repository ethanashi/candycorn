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
        #expect(state.aiProvider == .onDeviceWhenAvailable)
        state.setAIProvider(.router)
        #expect(state.aiProvider == .off)
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
}
