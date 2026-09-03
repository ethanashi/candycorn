import Foundation

enum ProvenanceVoice: String, Codable, CaseIterable, Sendable {
    case user
    case provider
    case candyCorn = "candy-corn"
}

struct Provenance: Codable, Equatable, Sendable {
    var voice: ProvenanceVoice
    var label: String
    var detail: String
    var occurredAt: Date?
    var sourceRoute: Route?
}

struct JournalEntry: Identifiable, Codable, Equatable, Sendable {
    enum InputType: String, Codable, Sendable { case text, voice, photo }
    enum ProcessingStatus: String, Codable, Sendable { case unprocessed, processing, processed, failed }

    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    let inputType: InputType
    var title: String
    var rawText: String
    var cleanedText: String?
    var summaryItems: [String]
    var originalAttachmentID: UUID?
    var audioAttachmentID: UUID?
    var moodLogID: UUID?
    var pinnedForNextAppointment: Bool
    var processingStatus: ProcessingStatus
    var provenance: Provenance
}

struct MoodLog: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    var mood: Int?
    var anxiety: Int?
    var energy: Int?
    var customValues: [String: Int]
    var note: String?

    func normalized() -> MoodLog {
        var copy = self
        copy.mood = Self.clamp(mood)
        copy.anxiety = Self.clamp(anxiety)
        copy.energy = Self.clamp(energy)
        copy.customValues = customValues.mapValues { min(max($0, 1), 10) }
        return copy
    }

    private static func clamp(_ value: Int?) -> Int? {
        value.map { min(max($0, 1), 10) }
    }
}

struct Appointment: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable { case therapy, tms, psychiatry, other }
    enum Status: String, Codable, Sendable { case planned, recording, processing, completed }

    let id: UUID
    var kind: Kind
    var scheduledAt: Date?
    var startedAt: Date?
    var endedAt: Date?
    var providerID: UUID?
    var providerName: String
    var recordingAttachmentID: UUID?
    var transcriptID: UUID?
    var summaryID: UUID?
    var status: Status
    var manualNotes: String = ""
}

struct Goal: Identifiable, Codable, Equatable, Sendable {
    enum Cadence: String, Codable, CaseIterable, Sendable {
        case oneOff
        case daily
        case weekly
        case monthly
        case ongoing
        case observation
        case homework
    }
    enum Source: String, Codable, Sendable { case userExplicit, providerExplicit, aiSuggested }
    enum Status: String, Codable, Sendable { case proposed, active, completed, paused, dismissed }

    let id: UUID
    var title: String
    var detail: String?
    var cadence: Cadence
    var source: Source
    var sourceEntityID: UUID?
    var sourceTimestampMilliseconds: Int?
    var status: Status
    let createdAt: Date
    var targetDate: Date?
    var provenance: Provenance
}

struct TalkingPoint: Identifiable, Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable { case manual, journal, session, aiSuggestion }
    enum Status: String, Codable, Sendable { case open, discussed, dismissed }

    let id: UUID
    var text: String
    var source: Source
    var sourceID: UUID?
    var targetAppointmentKind: Appointment.Kind?
    var isImportant: Bool
    var status: Status
    let createdAt: Date
    var provenance: Provenance
}

struct AIArtifact: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case journalRewrite
        case journalSummary
        case journalSignals
        case photoText
        case transcript
        case diarization
        case sessionSummary
        case appointmentBrief
        case goalSuggestions
        case goalProgressSuggestions
        case connectionSuggestion
    }

    let id: UUID
    let kind: Kind
    let sourceIDs: [UUID]
    let provider: String
    let model: String
    let structuredPayload: Data
    let createdAt: Date
}

enum GoalProgressMark: String, Codable, CaseIterable, Sendable {
    case doneToday
    case partial
    case blocked
}

struct TranscriptSegment: Identifiable, Codable, Equatable, Sendable {
    enum Speaker: String, Codable, Sendable { case patient, provider, unknown }

    let id: UUID
    let appointmentID: UUID
    var speaker: Speaker
    var rawSpeakerLabel: String?
    let startMilliseconds: Int
    let endMilliseconds: Int
    var text: String
    var confidence: Double?
}

enum SessionProcessingStage: String, Codable, CaseIterable, Sendable {
    case recordingSaved
    case transcribing
    case separatingSpeakers
    case summarizing
    case ready
}

enum SessionProcessingFailureCode: String, Codable, Sendable {
    case recordingMissing
    case transcriptionUnavailable
    case transcriptionFailed
    case modelDownloadOffline
    case diarizationFailed
    case summaryPermissionRequired
    case summaryFailed
}

struct SessionProcessingFailure: Codable, Equatable, Sendable {
    let code: SessionProcessingFailureCode
    let message: String
}

struct SessionProcessingRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let appointmentID: UUID
    var stage: SessionProcessingStage
    var progress: Double?
    var summaryConsentGranted: Bool
    var failure: SessionProcessingFailure?
    var updatedAt: Date
}

struct SpeakerClusterAssignment: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let appointmentID: UUID
    let rawSpeakerLabel: String
    var speaker: TranscriptSegment.Speaker
    var updatedAt: Date
}

struct PatientVoiceProfile: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let modelID: String
    let embedding: [Float]
    let createdAt: Date
}

enum SessionDebriefDecisionKind: String, Codable, Sendable {
    case addedHomework
    case addedGoal
    case ignoredGoal
    case markedTalkingPointDiscussed
    case pinnedQuestion
}

struct SessionDebriefDecision: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let appointmentID: UUID
    let summaryItemID: UUID
    let kind: SessionDebriefDecisionKind
    let targetEntityID: UUID?
    let editedText: String?
    let createdAt: Date
}

enum SessionDebriefMutation: Sendable {
    case addGoal(decision: SessionDebriefDecision, goal: Goal)
    case ignoreGoal(decision: SessionDebriefDecision)
    case markTalkingPointDiscussed(decision: SessionDebriefDecision, talkingPoint: TalkingPoint)
    case pinQuestion(decision: SessionDebriefDecision, talkingPoint: TalkingPoint)
}

enum AttachmentKind: String, Codable, Sendable {
    case audio
    case image
    case document
}

struct Attachment: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let kind: AttachmentKind
    let relativePath: String
    let mediaType: String
    let byteCount: Int64
    let durationMilliseconds: Int?
    let createdAt: Date
    let isSample: Bool
}

struct ProviderProfile: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var appointmentKind: Appointment.Kind
    var isSample: Bool
}

struct GoalProgress: Identifiable, Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case userConfirmed
        case aiSuggestedProgress
    }

    let id: UUID
    let goalID: UUID
    var sourceEntryID: UUID?
    var note: String
    var source: Source
    let createdAt: Date
    var mark: GoalProgressMark? = nil
}

struct VaultSettings: Codable, Equatable, Sendable {
    var useSampleContent: Bool
    var audioRetention: AudioRetentionChoice
    var aiMode: AIMode
    var aiProvider: AIProvider
}

struct CareSnapshot: Sendable, Equatable {
    var journals: [JournalEntry]
    var moods: [MoodLog]
    var appointments: [Appointment]
    var goals: [Goal]
    var goalProgress: [GoalProgress]
    var talkingPoints: [TalkingPoint]
    var artifacts: [AIArtifact]
    var attachments: [Attachment]
    var providers: [ProviderProfile]
    var transcript: [TranscriptSegment]
    var settings: VaultSettings
    var sessionProcessing: [SessionProcessingRecord] = []
    var speakerAssignments: [SpeakerClusterAssignment] = []
    var speakerEmbeddings: [SpeakerEmbedding] = []
    var patientVoiceProfiles: [PatientVoiceProfile] = []
    var debriefDecisions: [SessionDebriefDecision] = []
}

enum SearchEntityKind: String, Codable, Sendable {
    case journal
    case mood
    case appointment
    case goal
    case talkingPoint
    case transcript
    case summary
}

struct SearchHit: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let entityID: UUID
    let kind: SearchEntityKind
    let title: String
    let excerpt: String
    let occurredAt: Date
}
