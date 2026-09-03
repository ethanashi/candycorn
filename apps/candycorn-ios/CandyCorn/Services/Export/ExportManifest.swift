import Foundation

struct ExportManifest: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let createdAt: Date
    let journals: [ExportJournal]
    let moods: [ExportMood]
    let appointments: [ExportAppointment]
    let goals: [ExportGoal]
    let goalProgress: [ExportGoalProgress]
    let talkingPoints: [ExportTalkingPoint]
    let artifacts: [ExportArtifact]
    let attachments: [ExportAttachment]
    let providers: [ExportProvider]
    let transcripts: [ExportTranscript]
    let settings: VaultSettings
    let warnings: [ExportWarning]
}

struct ExportJournal: Codable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let inputType: JournalEntry.InputType
    let title: String
    let rawText: String
    let cleanedText: String?
    let summaryItems: [String]
    let originalAttachmentID: UUID?
    let audioAttachmentID: UUID?
    let moodLogID: UUID?
    let pinnedForNextAppointment: Bool
    let processingStatus: JournalEntry.ProcessingStatus
    let provenance: Provenance
    let markdownPath: String
    let attachmentPaths: [String]
}

struct ExportMood: Codable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let mood: Int?
    let anxiety: Int?
    let energy: Int?
    let customValues: [String: Int]
    let note: String?
    let markdownPath: String
}

struct ExportAppointment: Codable, Equatable, Sendable {
    let id: UUID
    let kind: Appointment.Kind
    let scheduledAt: Date?
    let startedAt: Date?
    let endedAt: Date?
    let providerID: UUID?
    let providerName: String
    let recordingAttachmentID: UUID?
    let transcriptID: UUID?
    let summaryID: UUID?
    let status: Appointment.Status
    let manualNotes: String
    let markdownPath: String
    let recordingPath: String?
}

struct ExportGoal: Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let detail: String?
    let cadence: Goal.Cadence
    let source: Goal.Source
    let sourceEntityID: UUID?
    let sourceTimestampMilliseconds: Int?
    let status: Goal.Status
    let createdAt: Date
    let targetDate: Date?
    let provenance: Provenance
    let markdownPath: String
}

struct ExportGoalProgress: Codable, Equatable, Sendable {
    let id: UUID
    let goalID: UUID
    let sourceEntryID: UUID?
    let note: String
    let source: GoalProgress.Source
    let createdAt: Date
    let markdownPath: String
}

struct ExportTalkingPoint: Codable, Equatable, Sendable {
    let id: UUID
    let text: String
    let source: TalkingPoint.Source
    let sourceID: UUID?
    let targetAppointmentKind: Appointment.Kind?
    let isImportant: Bool
    let status: TalkingPoint.Status
    let createdAt: Date
    let provenance: Provenance
    let markdownPath: String
}

struct ExportArtifact: Codable, Equatable, Sendable {
    let id: UUID
    let kind: AIArtifact.Kind
    let sourceIDs: [UUID]
    let provider: String
    let model: String
    let structuredPayload: Data
    let createdAt: Date
    let exportPath: String
}

struct ExportAttachment: Codable, Equatable, Sendable {
    let id: UUID
    let kind: AttachmentKind
    let mediaType: String
    let byteCount: Int64
    let durationMilliseconds: Int?
    let createdAt: Date
    let isSample: Bool
    let exportPath: String?
}

struct ExportProvider: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let appointmentKind: Appointment.Kind
    let isSample: Bool
    let markdownPath: String
}

struct ExportTranscript: Codable, Equatable, Sendable {
    let id: UUID
    let appointmentID: UUID
    let speaker: TranscriptSegment.Speaker
    let rawSpeakerLabel: String?
    let startMilliseconds: Int
    let endMilliseconds: Int
    let text: String
    let confidence: Double?
    let exportPath: String
}

struct ExportWarning: Codable, Equatable, Sendable {
    enum Code: String, Codable, Sendable {
        case attachmentUnavailable = "attachment-unavailable"
    }

    let code: Code
    let attachmentID: UUID
    let message: String
}
