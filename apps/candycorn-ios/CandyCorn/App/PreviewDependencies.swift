import Foundation

enum PreviewDependencies {
    static func make(
        screenshotMode: Bool = false,
        scenario: ScreenshotScenario? = nil
    ) -> AppDependencies {
        let snapshot = screenshotSnapshot(scenario: scenario)
        let store = InMemoryCareStore(snapshot: snapshot)
        let attachments = InMemoryAttachmentStore(seedData: screenshotImageData(scenario: scenario))
        let keyStore = InMemoryOpenRouterAPIKeyStore()
        do {
            try keyStore.storeKey("fictional-screenshot-key-not-valid")
        } catch {
            preconditionFailure("The fixed preview key must satisfy local validation")
        }
        let configuration = InMemoryAIConfigurationStore()
        let languageModel = ScreenshotLanguageModel(configuration: configuration)
        let visionReader = ScreenshotVisionReader(configuration: configuration)
        let recording: any RecordingService = screenshotMode
            ? ScreenshotRecordingService(attachments: attachments)
            : FakeRecordingService(attachments: attachments)
        return AppDependencies(
            careStore: store,
            maintenance: store,
            attachments: attachments,
            recording: recording,
            playback: FakeAudioPlaybackService(),
            photos: FakePhotoAttachmentService(),
            exporter: FakeVaultExporter(store: store, attachments: attachments),
            logger: NoOpEventLogger(),
            languageModel: languageModel,
            visionReader: visionReader,
            openRouterKeyStore: keyStore,
            aiConfigurationStore: configuration,
            screenshotScenario: scenario,
            screenshotMode: screenshotMode,
            now: { Date(timeIntervalSince1970: 1_788_654_600) }
        )
    }

    private static func screenshotSnapshot(scenario: ScreenshotScenario?) -> CareSnapshot {
        var snapshot = SeededData.careSnapshot
        guard scenario == .photoSend else { return snapshot }
        let date = Date(timeIntervalSince1970: 1_788_654_600)
        let attachment = Attachment(
            id: ScreenshotScenario.photoAttachmentID,
            kind: .image,
            relativePath: "images/fictional-journal-page.jpg",
            mediaType: "image/jpeg",
            byteCount: 4,
            durationMilliseconds: nil,
            createdAt: date,
            isSample: true
        )
        let journal = JournalEntry(
            id: ScreenshotScenario.photoJournalID,
            createdAt: date,
            updatedAt: date,
            inputType: .photo,
            title: "Football notes on paper",
            rawText: "",
            cleanedText: nil,
            summaryItems: [],
            originalAttachmentID: attachment.id,
            audioAttachmentID: nil,
            moodLogID: nil,
            pinnedForNextAppointment: false,
            processingStatus: .unprocessed,
            provenance: Provenance(
                voice: .user,
                label: "You photographed this",
                detail: "Saved on this device",
                occurredAt: date,
                sourceRoute: .journalDetail
            )
        )
        snapshot.journals.insert(journal, at: 0)
        snapshot.attachments.insert(attachment, at: 0)
        return snapshot
    }

    private static func screenshotImageData(scenario: ScreenshotScenario?) -> [String: Data] {
        guard scenario == .photoSend else { return [:] }
        return ["images/fictional-journal-page.jpg": Data([0xff, 0xd8, 0xff, 0xd9])]
    }
}

actor InMemoryCareStore: CareStore, VaultMaintenance {
    private var current: CareSnapshot
    private let searchDelays: [String: Duration]

    init(snapshot: CareSnapshot = SeededData.careSnapshot, searchDelays: [String: Duration] = [:]) {
        current = snapshot
        self.searchDelays = searchDelays
    }

    func snapshot() -> CareSnapshot { current }

    func saveJournal(_ entry: JournalEntry) {
        Self.upsert(entry, in: &current.journals)
    }

    func deleteJournal(id: UUID) {
        current.journals.removeAll { $0.id == id }
    }

    func saveMood(_ mood: MoodLog) {
        Self.upsert(mood.normalized(), in: &current.moods)
    }

    func saveAppointment(_ appointment: Appointment) {
        Self.upsert(appointment, in: &current.appointments)
    }

    func saveGoal(_ goal: Goal) {
        Self.upsert(goal, in: &current.goals)
    }

    func addGoalProgress(_ progress: GoalProgress) {
        guard !current.goalProgress.contains(where: { $0.id == progress.id }) else { return }
        current.goalProgress.append(progress)
    }

    func saveTalkingPoint(_ point: TalkingPoint) {
        Self.upsert(point, in: &current.talkingPoints)
    }

    func saveAttachment(_ attachment: Attachment) {
        Self.upsert(attachment, in: &current.attachments)
    }

    func saveArtifact(_ artifact: AIArtifact) {
        Self.upsert(artifact, in: &current.artifacts)
    }

    func deleteArtifact(id: UUID) {
        current.artifacts.removeAll { $0.id == id }
    }

    func search(_ query: String, limit: Int) async throws -> [SearchHit] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty, limit > 0 else { return [] }
        if let delay = searchDelays[term] {
            try await Task.sleep(for: delay)
        }
        var hits: [SearchHit] = []
        for entry in current.journals.prefix(500) {
            let searchable = "\(entry.title) \(entry.rawText) \(entry.cleanedText ?? "") \(entry.summaryItems.joined(separator: " "))".lowercased()
            guard searchable.contains(term) else { continue }
            hits.append(SearchHit(id: "journal:\(entry.id)", entityID: entry.id, kind: .journal, title: entry.title, excerpt: Self.excerpt(entry.rawText), occurredAt: entry.createdAt))
        }
        for goal in current.goals.prefix(500) where goal.title.lowercased().contains(term) || (goal.detail?.lowercased().contains(term) == true) {
            hits.append(SearchHit(id: "goal:\(goal.id)", entityID: goal.id, kind: .goal, title: goal.title, excerpt: Self.excerpt(goal.detail ?? goal.title), occurredAt: goal.createdAt))
        }
        for point in current.talkingPoints.prefix(500) where point.text.lowercased().contains(term) {
            hits.append(SearchHit(id: "talking-point:\(point.id)", entityID: point.id, kind: .talkingPoint, title: "Bring up next time", excerpt: Self.excerpt(point.text), occurredAt: point.createdAt))
        }
        for appointment in current.appointments.prefix(500) {
            let searchable = "\(appointment.providerName) \(appointment.manualNotes) \(appointment.kind.rawValue)".lowercased()
            guard searchable.contains(term) else { continue }
            let occurredAt = appointment.startedAt ?? appointment.scheduledAt ?? .distantPast
            hits.append(SearchHit(id: "appointment:\(appointment.id)", entityID: appointment.id, kind: .appointment, title: "\(appointment.kind.displayName) with \(appointment.providerName)", excerpt: Self.excerpt(appointment.manualNotes), occurredAt: occurredAt))
        }
        for mood in current.moods.prefix(500) where mood.note?.lowercased().contains(term) == true {
            hits.append(SearchHit(id: "mood:\(mood.id)", entityID: mood.id, kind: .mood, title: "Mood check-in", excerpt: Self.excerpt(mood.note ?? ""), occurredAt: mood.createdAt))
        }
        return Array(hits.sorted { $0.occurredAt > $1.occurredAt }.prefix(min(limit, 100)))
    }

    func setSampleContentEnabled(_ enabled: Bool) {
        current.settings.useSampleContent = enabled
        if enabled {
            mergeSamples()
        } else {
            removeSamples()
        }
    }

    func updateSettings(_ settings: VaultSettings) {
        current.settings = settings
    }

    func destroyAndRecreateVault() {
        current = SeededData.emptySnapshot
    }

    private static func upsert<Value: Identifiable>(_ value: Value, in values: inout [Value]) where Value.ID == UUID {
        if let index = values.firstIndex(where: { $0.id == value.id }) {
            values[index] = value
        } else {
            values.append(value)
        }
    }

    private static func excerpt(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Saved on this device" : String(trimmed.prefix(240))
    }

    private func removeSamples() {
        let journalIDs = Set(SeededData.journalEntries.map(\.id))
        let moodIDs = Set(SeededData.moodLogs.map(\.id))
        let appointmentIDs = Set(SeededData.appointments.map(\.id))
        let goalIDs = Set(SeededData.goals.map(\.id))
        let pointIDs = Set(SeededData.talkingPoints.map(\.id))
        current.journals.removeAll { journalIDs.contains($0.id) }
        current.moods.removeAll { moodIDs.contains($0.id) }
        current.appointments.removeAll { appointmentIDs.contains($0.id) }
        current.goals.removeAll { goalIDs.contains($0.id) }
        current.talkingPoints.removeAll { pointIDs.contains($0.id) }
        current.attachments.removeAll { $0.isSample }
        current.providers.removeAll { $0.isSample }
        current.transcript.removeAll { SeededData.transcript.map(\.id).contains($0.id) }
        current.artifacts.removeAll { SeededData.aiArtifacts.map(\.id).contains($0.id) }
    }

    private func mergeSamples() {
        for value in SeededData.journalEntries { Self.upsert(value, in: &current.journals) }
        for value in SeededData.moodLogs { Self.upsert(value, in: &current.moods) }
        for value in SeededData.appointments { Self.upsert(value, in: &current.appointments) }
        for value in SeededData.goals { Self.upsert(value, in: &current.goals) }
        for value in SeededData.talkingPoints { Self.upsert(value, in: &current.talkingPoints) }
        for value in SeededData.aiArtifacts { Self.upsert(value, in: &current.artifacts) }
        for value in SeededData.attachments { Self.upsert(value, in: &current.attachments) }
        for value in SeededData.providers { Self.upsert(value, in: &current.providers) }
        for value in SeededData.transcript { Self.upsert(value, in: &current.transcript) }
    }
}

actor InMemoryAttachmentStore: AttachmentStore {
    private let seedData: [String: Data]

    init(seedData: [String: Data] = [:]) {
        self.seedData = seedData
    }

    func allocateURL(kind: AttachmentKind, fileExtension: String) throws -> URL {
        guard !fileExtension.isEmpty else { throw UserFacingError.saving }
        return FileManager.default.temporaryDirectory
            .appending(path: kind.rawValue)
            .appendingPathExtension(fileExtension)
    }

    func url(for attachment: Attachment) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: attachment.relativePath)
        if let data = seedData[attachment.relativePath] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        return url
    }

    func copyIntoExport(_ attachment: Attachment, destination: URL) throws {
        guard !attachment.relativePath.isEmpty, destination.isFileURL else { throw UserFacingError.export }
    }

    func removeAll() {}
}

actor FakeRecordingService: RecordingService {
    private let attachments: any AttachmentStore
    private var authorization: CaptureAuthorization
    private var activeKind: RecordingKind?
    private let stream: AsyncStream<RecordingEvent>
    private let continuation: AsyncStream<RecordingEvent>.Continuation

    init(authorization: CaptureAuthorization = .authorized, attachments: any AttachmentStore = InMemoryAttachmentStore()) {
        self.authorization = authorization
        self.attachments = attachments
        let pair = AsyncStream.makeStream(of: RecordingEvent.self, bufferingPolicy: .bufferingNewest(20))
        stream = pair.stream
        continuation = pair.continuation
    }

    func authorizationStatus() -> CaptureAuthorization { authorization }

    func requestPermission() -> Bool {
        if authorization == .notDetermined { authorization = .authorized }
        return authorization == .authorized
    }

    func start(kind: RecordingKind) throws {
        guard authorization == .authorized, activeKind == nil else { throw UserFacingError.recording }
        activeKind = kind
        continuation.yield(.snapshot(RecordingSnapshot(elapsedMilliseconds: 0, normalizedLevel: 0, isRecording: true)))
    }

    func stop(reason: RecordingStopReason) async throws -> LocalRecording {
        guard activeKind != nil else { throw UserFacingError.recording }
        activeKind = nil
        let url = try await attachments.allocateURL(kind: .audio, fileExtension: "m4a")
        let attachment = Attachment(id: UUID(), kind: .audio, relativePath: "audio/recording.m4a", mediaType: "audio/mp4", byteCount: 1_024, durationMilliseconds: 1_000, createdAt: Date(timeIntervalSince1970: 1_788_654_600), isSample: false)
        let recording = LocalRecording(attachment: attachment, fileURL: url, stopReason: reason)
        continuation.yield(.stopped(recording))
        return recording
    }

    func events() -> AsyncStream<RecordingEvent> { stream }
}

actor FakeAudioPlaybackService: AudioPlaybackService {
    func play(attachment: Attachment) throws {
        guard attachment.byteCount > 0 else { throw UserFacingError.playback }
    }
    func pause() {}
    func stop() {}
    func events() -> AsyncStream<RecordingSnapshot> { AsyncStream { $0.finish() } }
}

actor FakePhotoAttachmentService: PhotoAttachmentService {
    private var authorization: CaptureAuthorization

    init(authorization: CaptureAuthorization = .authorized) {
        self.authorization = authorization
    }

    func authorizationStatus() -> CaptureAuthorization { authorization }
    func requestPermission() -> Bool {
        if authorization == .notDetermined { authorization = .authorized }
        return authorization == .authorized
    }

    func saveJPEG(_ data: Data, pixelWidth: Int, pixelHeight: Int) throws -> Attachment {
        guard !data.isEmpty, pixelWidth > 0, pixelHeight > 0 else { throw UserFacingError.saving }
        return Attachment(id: UUID(), kind: .image, relativePath: "images/journal.jpg", mediaType: "image/jpeg", byteCount: Int64(data.count), durationMilliseconds: nil, createdAt: Date(timeIntervalSince1970: 1_788_654_600), isSample: false)
    }
}

actor FakeVaultExporter: VaultExporting {
    private let store: any CareStore
    private let attachments: any AttachmentStore

    init(store: any CareStore, attachments: any AttachmentStore) {
        self.store = store
        self.attachments = attachments
    }

    func makeExport() async throws -> ExportPackage {
        _ = try await store.snapshot()
        return ExportPackage(directoryURL: FileManager.default.temporaryDirectory.appending(path: "Candy Corn export"), createdAt: Date(timeIntervalSince1970: 1_788_654_600))
    }

    func cleanup(_ package: ExportPackage) async {
        _ = package.directoryURL
    }

    func deleteEverything(confirmation: DeleteConfirmation) async throws {
        guard confirmation.accepted, let maintenance = store as? any VaultMaintenance else { throw UserFacingError.saving }
        try await maintenance.destroyAndRecreateVault()
        try await attachments.removeAll()
    }
}

struct NoOpEventLogger: EventLogging {
    func record(_ name: EventName, metrics: EventMetrics) {
        _ = name
        _ = metrics
    }
}

final class InMemoryAIConfigurationStore: AIConfigurationProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var value: AIModelConfiguration

    init(value: AIModelConfiguration = .defaults) {
        self.value = value
    }

    func load() -> AIModelConfiguration {
        lock.withLock { value }
    }

    func save(_ configuration: AIModelConfiguration) throws {
        let organizer = configuration.organizerModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let vision = configuration.visionModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !organizer.isEmpty, !vision.isEmpty else { throw AIConfigurationStoreError.invalidModelIdentifier }
        lock.withLock { value = AIModelConfiguration(organizerModelID: organizer, visionModelID: vision) }
    }

    func reset() throws {
        lock.withLock { value = .defaults }
    }
}

actor ScreenshotLanguageModel: CandyCornLanguageModel {
    nonisolated let id = "screenshot-organizer"
    private let configuration: any AIConfigurationProviding

    init(configuration: any AIConfigurationProviding) {
        self.configuration = configuration
    }

    func rewriteJournal(_ input: RewriteJournalInput) throws -> RewriteJournalResult {
        let citation = try Self.citation(input.source)
        let segment = RewriteSegment(
            id: UUID(uuid: (0x91, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 1)),
            text: "Football thoughts interrupted the afternoon. Exercise helped, then guilt followed the relief.",
            evidence: [citation]
        )
        return RewriteJournalResult(segments: [segment], unclearAreas: [], metadata: metadata())
    }

    func summarizeJournal(_ input: JournalSummaryInput) throws -> JournalSummaryResult {
        let statement = try Self.statement(input.source, text: "Exercise helped before guilt returned.")
        return JournalSummaryResult(statements: [statement], metadata: metadata())
    }

    func extractJournalSignals(_ input: JournalSignalInput) throws -> JournalSignalResult {
        let quote = try Self.quote(input.source)
        let point = JournalSignals.TalkingPointSuggestion(
            id: UUID(uuid: (0x92, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 1)),
            text: "Ask why relief can be followed by guilt.",
            reason: "This is a suggestion grounded in the journal.",
            evidence: quote
        )
        let signals = JournalSignals(
            summary: "Exercise helped before guilt returned.",
            emotions: [.init(label: "Guilt", evidence: quote)],
            explicitCommitments: [],
            talkingPointSuggestions: [point],
            possibleThemes: [.init(label: "Relief and guilt", evidence: quote)]
        )
        return JournalSignalResult(signals: signals, metadata: metadata())
    }

    func summarizeSession(_ input: SessionSummaryInput) throws -> SessionSummaryResult {
        let statement = try Self.statement(input.manualNotes, text: "The session returned to football and guilt.")
        let section = SessionSummarySection(
            id: UUID(uuid: (0x93, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 1)),
            title: "What came up",
            statements: [statement]
        )
        return SessionSummaryResult(sections: [section], metadata: metadata())
    }

    func generateAppointmentBrief(_ input: AppointmentBriefInput) throws -> AppointmentBriefResult {
        guard let source = input.sources.first else { throw AIProviderError.invalidInput }
        let statement = try Self.statement(source, text: "Start with the most recent care context.")
        let section = AppointmentBriefSection(
            id: UUID(uuid: (0x94, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 1)),
            title: "Where to begin",
            statements: [statement]
        )
        return AppointmentBriefResult(sections: [section], userEditedAt: nil, metadata: metadata())
    }

    private func metadata() -> AIResultMetadata {
        AIResultMetadata(provider: id, model: configuration.load().organizerModelID, usage: AIUsage())
    }

    private static func quote(_ source: SourceTextDocument) throws -> String {
        let value = source.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw AIProviderError.invalidInput }
        return String(value.prefix(1_000))
    }

    private static func citation(_ source: SourceTextDocument) throws -> EvidenceCitation {
        EvidenceCitation(sourceID: source.id, quote: try quote(source), timestampMilliseconds: nil)
    }

    private static func statement(_ source: SourceTextDocument, text: String) throws -> EvidenceBackedStatement {
        EvidenceBackedStatement(id: UUID(), text: text, evidence: [try citation(source)])
    }
}

actor ScreenshotVisionReader: CandyCornVisionReader {
    nonisolated let id = "screenshot-vision"
    private let configuration: any AIConfigurationProviding

    init(configuration: any AIConfigurationProviding) {
        self.configuration = configuration
    }

    func extractText(from input: VisionReadInput) throws -> VisionReadResult {
        guard !input.imageData.isEmpty else { throw AIProviderError.invalidInput }
        return VisionReadResult(
            text: "I want to bring up football and the guilt that followed feeling better.",
            uncertainSpans: ["followed feeling better"],
            metadata: AIResultMetadata(
                provider: id,
                model: configuration.load().visionModelID,
                usage: AIUsage()
            )
        )
    }
}
