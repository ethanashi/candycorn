import Foundation
import Observation

enum AIMode: String, CaseIterable, Codable, Sendable {
    case off
    case organizer
    case reflection
}

enum AIProvider: String, CaseIterable, Codable, Sendable {
    case onDeviceWhenAvailable
    case router
    case off
}

enum RecordingDemoStatus: Equatable, Sendable {
    case idle
    case recording(startSeconds: Int)
    case saved(durationSeconds: Int)
}

@MainActor @Observable
final class DemoState {
    private(set) var mood: MoodLog?
    private(set) var goals: [Goal]
    private(set) var talkingPoints: [TalkingPoint]
    private(set) var transcript: [TranscriptSegment]
    private(set) var speakerCorrections: [UUID: TranscriptSegment.Speaker]
    var aiMode: AIMode
    var aiProvider: AIProvider
    var routerAvailable: Bool
    var consentAcknowledged: Bool
    var selectedAppointmentKind: Appointment.Kind
    private(set) var appointmentRecording: RecordingDemoStatus

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        mood = nil
        goals = []
        talkingPoints = []
        transcript = []
        speakerCorrections = [:]
        aiMode = .organizer
        aiProvider = .router
        routerAvailable = true
        consentAcknowledged = false
        selectedAppointmentKind = .therapy
        appointmentRecording = .idle
        reset()
        if Route.parseLaunchArguments(arguments) == .activeAppointment {
            consentAcknowledged = true
            appointmentRecording = .recording(startSeconds: 0)
        }
    }

    func saveMood(_ mood: MoodLog?) {
        self.mood = mood?.normalized()
    }

    @discardableResult
    func addGoal(_ goal: Goal) -> Bool {
        guard !goals.contains(where: { $0.id == goal.id }) else { return false }
        goals.append(goal)
        return true
    }

    func toggleGoal(id: UUID) {
        guard let index = goals.firstIndex(where: { $0.id == id }) else { return }
        goals[index].status = goals[index].status == .completed ? .active : .completed
    }

    @discardableResult
    func addTalkingPoint(_ point: TalkingPoint) -> Bool {
        guard !talkingPoints.contains(where: { $0.id == point.id }) else { return false }
        talkingPoints.append(point)
        return true
    }

    func updateTalkingPoint(id: UUID, status: TalkingPoint.Status) {
        guard let index = talkingPoints.firstIndex(where: { $0.id == id }) else { return }
        talkingPoints[index].status = status
    }

    func setAIMode(_ mode: AIMode) {
        aiMode = mode
        if mode == .off {
            aiProvider = .off
        } else if aiProvider == .off {
            aiProvider = routerAvailable ? .router : .onDeviceWhenAvailable
        }
    }

    func setAIProvider(_ provider: AIProvider) {
        guard aiMode != .off else {
            aiProvider = .off
            return
        }
        if provider == .router && !routerAvailable {
            aiProvider = .off
        } else {
            aiProvider = provider
        }
    }

    func selectAppointmentKind(_ kind: Appointment.Kind) {
        guard selectedAppointmentKind != kind else { return }
        selectedAppointmentKind = kind
        consentAcknowledged = false
        appointmentRecording = .idle
    }

    @discardableResult
    func startAppointmentRecording() -> Bool {
        guard consentAcknowledged, appointmentRecording == .idle else { return false }
        appointmentRecording = .recording(startSeconds: 0)
        return true
    }

    @discardableResult
    func finishAppointmentRecording(durationSeconds: Int) -> Bool {
        guard durationSeconds >= 0 else { return false }
        guard case .recording = appointmentRecording else { return false }
        appointmentRecording = .saved(durationSeconds: durationSeconds)
        return true
    }

    @discardableResult
    func correctSpeaker(segmentID: UUID, to speaker: TranscriptSegment.Speaker) -> Bool {
        guard speaker != .unknown else { return false }
        guard let segment = transcript.first(where: { $0.id == segmentID }) else { return false }
        guard segment.speaker == .unknown, speakerCorrections[segmentID] == nil else { return false }
        speakerCorrections[segmentID] = speaker
        return true
    }

    func reset() {
        mood = SeededData.moodLogs.first
        goals = SeededData.goals
        talkingPoints = SeededData.talkingPoints
        transcript = SeededData.transcript
        speakerCorrections = [:]
        aiMode = .organizer
        aiProvider = .router
        routerAvailable = true
        consentAcknowledged = false
        selectedAppointmentKind = .therapy
        appointmentRecording = .idle
    }
}
