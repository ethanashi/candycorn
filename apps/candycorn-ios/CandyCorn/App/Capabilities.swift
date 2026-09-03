import Foundation

enum CaptureAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

protocol CareStore: Sendable {
    func snapshot() async throws -> CareSnapshot
    func saveJournal(_ entry: JournalEntry) async throws
    func deleteJournal(id: UUID) async throws
    func saveMood(_ mood: MoodLog) async throws
    func saveAppointment(_ appointment: Appointment) async throws
    func saveGoal(_ goal: Goal) async throws
    func addGoalProgress(_ progress: GoalProgress) async throws
    func saveTalkingPoint(_ point: TalkingPoint) async throws
    func saveAttachment(_ attachment: Attachment) async throws
    func search(_ query: String, limit: Int) async throws -> [SearchHit]
    func setSampleContentEnabled(_ enabled: Bool) async throws
    func updateSettings(_ settings: VaultSettings) async throws
}

protocol VaultMaintenance: Sendable {
    func destroyAndRecreateVault() async throws
}

protocol AttachmentStore: Sendable {
    func allocateURL(kind: AttachmentKind, fileExtension: String) async throws -> URL
    func url(for attachment: Attachment) async throws -> URL
    func copyIntoExport(_ attachment: Attachment, destination: URL) async throws
    func removeAll() async throws
}

enum RecordingKind: Sendable, Equatable {
    case journal
    case appointment(id: UUID)
}

enum RecordingStopReason: String, Sendable, Equatable {
    case user
    case interruption
    case failure
}

struct RecordingSnapshot: Sendable, Equatable {
    var elapsedMilliseconds: Int
    var normalizedLevel: Float
    var isRecording: Bool
}

struct LocalRecording: Sendable, Equatable {
    let attachment: Attachment
    let fileURL: URL
    let stopReason: RecordingStopReason
}

enum RecordingEvent: Sendable, Equatable {
    case snapshot(RecordingSnapshot)
    case stopped(LocalRecording)
    case failed(message: String)
}

protocol RecordingService: Sendable {
    func authorizationStatus() async -> CaptureAuthorization
    func requestPermission() async -> Bool
    func start(kind: RecordingKind) async throws
    func stop(reason: RecordingStopReason) async throws -> LocalRecording
    func events() async -> AsyncStream<RecordingEvent>
}

protocol AudioPlaybackService: Sendable {
    func play(attachment: Attachment) async throws
    func pause() async
    func stop() async
    func events() async -> AsyncStream<RecordingSnapshot>
}

protocol PhotoAttachmentService: Sendable {
    func authorizationStatus() async -> CaptureAuthorization
    func requestPermission() async -> Bool
    func saveJPEG(_ data: Data, pixelWidth: Int, pixelHeight: Int) async throws -> Attachment
}

struct ExportPackage: Sendable, Equatable {
    let directoryURL: URL
    let createdAt: Date
}

struct DeleteConfirmation: Sendable, Equatable {
    let accepted: Bool

    init?(typedText: String) {
        guard typedText == "DELETE" else { return nil }
        accepted = true
    }
}

protocol VaultExporting: Sendable {
    func makeExport() async throws -> ExportPackage
    func cleanup(_ package: ExportPackage) async
    func deleteEverything(confirmation: DeleteConfirmation) async throws
}

enum EventName: String, Sendable {
    case vaultOpened
    case migrationCompleted
    case journalSaved
    case moodSaved
    case recordingStarted
    case recordingStopped
    case attachmentSaved
    case searchCompleted
    case exportCompleted
    case vaultDeleted
}

struct EventMetrics: Sendable, Equatable {
    var durationMilliseconds: Int?
    var count: Int?

    init(durationMilliseconds: Int? = nil, count: Int? = nil) {
        self.durationMilliseconds = durationMilliseconds
        self.count = count
    }
}

protocol EventLogging: Sendable {
    func record(_ name: EventName, metrics: EventMetrics)
}

struct AppDependencies: Sendable {
    let careStore: any CareStore
    let maintenance: any VaultMaintenance
    let attachments: any AttachmentStore
    let recording: any RecordingService
    let playback: any AudioPlaybackService
    let photos: any PhotoAttachmentService
    let exporter: any VaultExporting
    let logger: any EventLogging
    let screenshotMode: Bool
    let now: @Sendable () -> Date
}

struct UserFacingError: Error, Equatable, Sendable {
    let message: String

    static let loading = UserFacingError(message: "Your care vault could not be opened. Try again.")
    static let saving = UserFacingError(message: "That change could not be saved. Try again.")
    static let recording = UserFacingError(message: "Recording could not start. Your existing entries are unchanged.")
    static let playback = UserFacingError(message: "This recording is not available for playback.")
    static let export = UserFacingError(message: "Your export could not be created. Try again.")
}
