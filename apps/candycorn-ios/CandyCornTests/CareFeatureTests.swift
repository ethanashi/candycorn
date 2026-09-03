import Foundation
import Testing
@testable import CandyCorn

@Suite("Care features")
@MainActor
struct CareFeatureTests {
    @Test("Appointment timer and transcript timestamps are deterministic")
    func formatting() {
        #expect(AppointmentRecordingClock.format(seconds: 1_104) == "18:24")
        #expect(AppointmentRecordingClock.format(seconds: -1) == "00:00")
        #expect(AppointmentRecordingClock.format(milliseconds: 744_999) == "12:24")
        #expect(AppointmentRecordingClock.format(milliseconds: -1) == "0:00")
    }

    @Test("Timer ticks, cancels, and finishes once")
    func clockLifecycle() {
        var clock = AppointmentRecordingClock()
        clock.tick()
        #expect(clock.elapsedSeconds == 1_105)
        let firstFinish = clock.finish()
        let repeatedFinish = clock.finish()
        #expect(firstFinish)
        #expect(!repeatedFinish)
        clock.tick()
        #expect(clock.elapsedSeconds == 1_105)
        clock.cancel()
        #expect(!clock.isRunning)
    }

    @Test("Consent resets by type and gates idempotent recording")
    func consentAndRecording() {
        let state = DemoState(arguments: ["CandyCorn"])
        #expect(!state.startAppointmentRecording())
        state.consentAcknowledged = true
        #expect(state.startAppointmentRecording())
        #expect(!state.startAppointmentRecording())
        #expect(state.finishAppointmentRecording(durationSeconds: 1_104))
        #expect(!state.finishAppointmentRecording(durationSeconds: 1_105))
        state.selectAppointmentKind(.tms)
        #expect(!state.consentAcknowledged)
        #expect(state.appointmentRecording == .idle)
    }

    @Test("Summary evidence finds only existing transcript sources")
    func evidenceLookup() {
        let evidence = TherapySummaryEvidence.items[0]
        let segment = TherapySummaryEvidence.segment(for: evidence.id, in: SeededData.transcript)
        #expect(segment?.startMilliseconds == 744_000)
        #expect(TherapySummaryEvidence.segment(for: UUID(), in: SeededData.transcript) == nil)
    }

    @Test("Unknown speaker correction preserves source text")
    func speakerCorrection() throws {
        let state = DemoState()
        let unknown = try #require(state.transcript.first { $0.speaker == .unknown })
        let originalText = unknown.text
        #expect(state.correctSpeaker(segmentID: unknown.id, to: .provider))
        #expect(!state.correctSpeaker(segmentID: unknown.id, to: .patient))
        #expect(state.transcript.first { $0.id == unknown.id }?.text == originalText)
        #expect(state.speakerCorrections[unknown.id] == .provider)
    }

    @Test("TMS measures stay in the one through ten range")
    func tmsRange() {
        var snapshot = TMSCheckInSnapshot(mood: 0, anxiety: 11, energy: 4, distress: 6)
        #expect(snapshot.mood == 1)
        #expect(snapshot.anxiety == 10)
        let lowUpdate = snapshot.update(.distress, value: 0)
        let highUpdate = snapshot.update(.mood, value: 11)
        let validUpdate = snapshot.update(.energy, value: 10)
        #expect(!lowUpdate)
        #expect(!highUpdate)
        #expect(validUpdate)
        #expect(snapshot.energy == 10)
        #expect(TMSCheckInSnapshot.contains(1))
        #expect(TMSCheckInSnapshot.contains(10))
    }
}
