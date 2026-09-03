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
    func saveArtifact(_ artifact: AIArtifact) async throws
    func deleteArtifact(id: UUID) async throws
    func search(_ query: String, limit: Int) async throws -> [SearchHit]
    func setSampleContentEnabled(_ enabled: Bool) async throws
    func updateSettings(_ settings: VaultSettings) async throws
}

extension CareStore {
    func saveArtifact(_ artifact: AIArtifact) async throws {
        _ = artifact.id
        throw AIProviderError.unavailable
    }

    func deleteArtifact(id: UUID) async throws {
        _ = id
        throw AIProviderError.unavailable
    }
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
    let languageModel: any CandyCornLanguageModel
    let visionReader: any CandyCornVisionReader
    let transcriber: any CandyCornTranscriber
    let distressClassifier: any DistressSupportClassifier
    let openRouterKeyStore: any OpenRouterAPIKeyProviding
    let aiConfigurationStore: any AIConfigurationProviding
    let organizer: OrganizerCoordinator
    let screenshotScenario: ScreenshotScenario?
    let screenshotMode: Bool
    let now: @Sendable () -> Date

    init(
        careStore: any CareStore,
        maintenance: any VaultMaintenance,
        attachments: any AttachmentStore,
        recording: any RecordingService,
        playback: any AudioPlaybackService,
        photos: any PhotoAttachmentService,
        exporter: any VaultExporting,
        logger: any EventLogging,
        languageModel: (any CandyCornLanguageModel)? = nil,
        visionReader: (any CandyCornVisionReader)? = nil,
        transcriber: any CandyCornTranscriber = UnavailableTranscriber(),
        distressClassifier: any DistressSupportClassifier = NoOpDistressSupportClassifier(),
        openRouterKeyStore: (any OpenRouterAPIKeyProviding)? = nil,
        aiConfigurationStore: (any AIConfigurationProviding)? = nil,
        organizer: OrganizerCoordinator? = nil,
        screenshotScenario: ScreenshotScenario? = nil,
        screenshotMode: Bool,
        now: @escaping @Sendable () -> Date
    ) {
        let keyStore = openRouterKeyStore ?? InMemoryOpenRouterAPIKeyStore()
        let configurationStore = aiConfigurationStore ?? InMemoryAIConfigurationStore()
        let resolvedLanguageModel = languageModel ?? AppleFoundationModelProvider()
        let resolvedVisionReader = visionReader ?? UnavailableVisionReader()
        self.careStore = careStore
        self.maintenance = maintenance
        self.attachments = attachments
        self.recording = recording
        self.playback = playback
        self.photos = photos
        self.exporter = exporter
        self.logger = logger
        self.languageModel = resolvedLanguageModel
        self.visionReader = resolvedVisionReader
        self.transcriber = transcriber
        self.distressClassifier = distressClassifier
        self.openRouterKeyStore = keyStore
        self.aiConfigurationStore = configurationStore
        self.organizer = organizer ?? OrganizerCoordinator(
            careStore: careStore,
            attachments: attachments,
            languageModel: resolvedLanguageModel,
            visionReader: resolvedVisionReader,
            now: now
        )
        self.screenshotScenario = screenshotScenario
        self.screenshotMode = screenshotMode
        self.now = now
    }
}

struct UserFacingError: Error, Equatable, Sendable {
    let message: String

    static let loading = UserFacingError(message: "Your care vault could not be opened. Try again.")
    static let saving = UserFacingError(message: "That change could not be saved. Try again.")
    static let recording = UserFacingError(message: "Recording could not start. Your existing entries are unchanged.")
    static let playback = UserFacingError(message: "This recording is not available for playback.")
    static let export = UserFacingError(message: "Your export could not be created. Try again.")
    static let aiUnavailable = UserFacingError(message: "AI processing is off or unavailable. Your source is unchanged.")
    static let aiSource = UserFacingError(message: "This source is not available for AI processing.")
    static let aiSelectionTooLarge = UserFacingError(message: "The required appointment context is over 50,000 characters. Remove or shorten a required item before sending.")
    static let aiStale = UserFacingError(message: "The source changed while Candy Corn was working. Review it and send again.")
    static let aiCanceled = UserFacingError(message: "AI processing was canceled. Review and send again when ready.")
}
