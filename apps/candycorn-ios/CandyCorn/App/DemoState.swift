import Foundation
import Observation

enum AIMode: String, CaseIterable, Codable, Sendable {
    case off
    case organizer
    case reflection
}

private struct PreparedAIContext: Equatable, Sendable {
    let pending: PendingAISend
    let payload: PreparedAIPayload
    let careRevision: Int
}

private enum BriefDisclosureStyle: Equatable, Sendable {
    case individualSources
    case contextPacket
}

private enum PreparedAIPayload: Equatable, Sendable {
    case journal(JournalEntry, SourceTextDocument)
    case photo(JournalEntry, Attachment)
    case session(Appointment, SourceTextDocument)
    case brief(AppointmentBriefInput, Int, BriefDisclosureStyle)
    case processedSession(ProcessedSessionAIContext)
    case goalProgress(GoalProgressSuggestionInput)
    case weeklySummary(WeeklySummaryInput)

    var sourceRevision: Date? {
        switch self {
        case let .journal(journal, _), let .photo(journal, _):
            journal.updatedAt
        case let .session(appointment, _):
            appointment.endedAt ?? appointment.startedAt ?? appointment.scheduledAt
        case let .brief(input, _, _):
            input.sources.compactMap(\.occurredAt).max()
        case let .processedSession(context):
            context.appointment.endedAt ?? context.appointment.startedAt ?? context.appointment.scheduledAt
        case let .goalProgress(input):
            input.sources.compactMap(\.document.occurredAt).max()
        case let .weeklySummary(input):
            input.sources.compactMap(\.document.occurredAt).max()
        }
    }

    var journalID: UUID? {
        switch self {
        case let .journal(journal, _), let .photo(journal, _): journal.id
        case .session, .brief, .processedSession, .goalProgress, .weeklySummary: nil
        }
    }
}

private struct ProcessedSessionAIContext: Equatable, Sendable {
    let appointment: Appointment
    let attachmentID: UUID
    let transcript: [SessionTranscriptSource]
    let talkingPoints: [SessionTalkingPointSource]
}

private struct AppointmentBriefPreparation: Sendable {
    let id: UUID
    let careRevision: Int
    let task: Task<ContextPacket, Error>
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

enum CareLoadState: Equatable, Sendable {
    case loading
    case loaded
    case empty
    case failed(String)
}

enum ExportViewState: Equatable, Sendable {
    case idle
    case exporting
    case ready(ExportPackage)
    case failed(String)
    case deleted
}

@MainActor @Observable
final class DemoState {
    let dependencies: AppDependencies
    private(set) var loadState: CareLoadState = .loading
    private(set) var journals: [JournalEntry]
    private(set) var moods: [MoodLog]
    private(set) var appointments: [Appointment]
    private(set) var goals: [Goal]
    private(set) var goalProgress: [GoalProgress]
    private(set) var talkingPoints: [TalkingPoint]
    private(set) var artifacts: [AIArtifact]
    private(set) var attachments: [Attachment]
    private(set) var providers: [ProviderProfile]
    private(set) var transcript: [TranscriptSegment]
    private(set) var sessionProcessing: [SessionProcessingRecord]
    private(set) var speakerAssignments: [SpeakerClusterAssignment]
    private(set) var debriefDecisions: [SessionDebriefDecision]
    private(set) var settings: VaultSettings
    private(set) var speakerCorrections: [UUID: TranscriptSegment.Speaker] = [:]
    private(set) var searchResults: [SearchHit] = []
    private(set) var searchState: CareLoadState = .empty
    private(set) var exportState: ExportViewState = .idle
    private(set) var recordingSnapshot = RecordingSnapshot(elapsedMilliseconds: 0, normalizedLevel: 0, isRecording: false)
    private(set) var latestRecording: LocalRecording?
    private(set) var operationError: String?
    private(set) var hasOpenRouterKey: Bool
    private(set) var aiConfiguration: AIModelConfiguration
    private(set) var selectedJournalID: UUID?
    private(set) var selectedAppointmentID: UUID?
    var routerAvailable = true
    var consentAcknowledged = false
    var selectedAppointmentKind: Appointment.Kind = .therapy
    private(set) var appointmentRecording: RecordingDemoStatus = .idle
    private var searchGeneration = 0
    private(set) var activeRecordingKind: RecordingKind?
    private var recordingEventsTask: Task<Void, Never>?
    private var processingEventsTask: Task<Void, Never>?
    private var busyGoalIDs: Set<UUID> = []
    private var busyTalkingPointIDs: Set<UUID> = []
    private var busyProgressSuggestionIDs: Set<UUID> = []
    private var preparedAISends: [UUID: PreparedAIContext] = [:]
    private var preparedAISendOrder: [UUID] = []
    private var appointmentBriefPreparations: [Appointment.Kind: AppointmentBriefPreparation] = [:]
    private var preparedAppointmentBriefIDs: [Appointment.Kind: UUID] = [:]
    private var preparedGoalProgressIDs: [GoalProgressSuggestionSource: UUID] = [:]
    private var preparedWeeklySummaryIDs: [Date: UUID] = [:]
    private var activeAISends: Set<AISendAction> = []
    private var aiProcessingStates: [AISendAction: AIProcessingState] = [:]
    private var careRevision = 0
    private var aiSettingsRevision = 0
    private var currentMoodID: UUID?
    private var busySpeakerClusters: Set<String> = []
    private let launchArguments: [String]

    var mood: MoodLog? {
        if let currentMoodID,
           let current = moods.first(where: { $0.id == currentMoodID }) {
            return current
        }
        return moods.max { $0.createdAt < $1.createdAt }
    }
    var aiMode: AIMode { settings.aiMode }
    var aiProvider: AIProvider { settings.aiProvider }
    var pendingProgressSuggestions: [GoalProgressSuggestion] {
        artifacts
            .filter { $0.kind == .goalProgressSuggestions }
            .sorted { ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString) }
            .prefix(256)
            .flatMap { artifact in
                (try? JSONDecoder().decode(
                    GoalProgressSuggestionArtifactPayload.self,
                    from: artifact.structuredPayload
                ))?.result.suggestions.filter { $0.resolution == .pending } ?? []
            }
    }
    var currentWeeklySummary: WeeklySummaryResult? {
        WeeklyConsolidator.currentSummary(in: artifacts, for: dependencies.now())
    }

    init(
        dependencies: AppDependencies? = nil,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        let screenshotMode = Route.parseLaunchArguments(arguments) != nil
        let resolvedDependencies = dependencies ?? PreviewDependencies.make(
            screenshotMode: screenshotMode,
            scenario: ScreenshotScenario.parse(arguments: arguments)
        )
        self.dependencies = resolvedDependencies
        launchArguments = arguments
        let base = dependencies == nil ? SeededData.careSnapshot : SeededData.emptySnapshot
        let initial = Phase5ScreenshotSeed.applyingIfNeeded(
            to: Phase4ScreenshotSeed.applyingIfNeeded(to: base, arguments: arguments),
            arguments: arguments, now: resolvedDependencies.now()
        )
        journals = initial.journals
        moods = initial.moods
        appointments = initial.appointments
        goals = initial.goals
        goalProgress = initial.goalProgress
        talkingPoints = initial.talkingPoints
        artifacts = initial.artifacts
        attachments = initial.attachments
        providers = initial.providers
        transcript = initial.transcript
        sessionProcessing = initial.sessionProcessing
        speakerAssignments = initial.speakerAssignments
        debriefDecisions = initial.debriefDecisions
        settings = initial.settings
        currentMoodID = Self.latestMoodID(in: initial.moods)
        hasOpenRouterKey = (try? resolvedDependencies.openRouterKeyStore.hasKey()) ?? false
        aiConfiguration = resolvedDependencies.aiConfigurationStore.load()
        routerAvailable = hasOpenRouterKey
        if Route.parseLaunchArguments(arguments) == .activeAppointment {
            consentAcknowledged = true
            appointmentRecording = .recording(startSeconds: 0)
        }
    }

    func load() async {
        loadState = .loading
        do {
            listenForProcessingEvents()
            apply(Phase5ScreenshotSeed.applyingIfNeeded(
                to: Phase4ScreenshotSeed.applyingIfNeeded(
                    to: try await dependencies.careStore.snapshot(), arguments: launchArguments
                ),
                arguments: launchArguments, now: dependencies.now()
            ))
            refreshLoadState()
            dependencies.logger.record(.vaultOpened, metrics: EventMetrics())
            await dependencies.sessionProcessing.resumePending()
        } catch {
            loadState = .failed(UserFacingError.loading.message)
        }
    }

    func saveMood(_ mood: MoodLog?) {
        careRevision += 1
        guard let mood else {
            moods = []
            currentMoodID = nil
            return
        }
        let normalized = mood.normalized()
        Self.upsert(normalized, in: &moods)
        currentMoodID = normalized.id
    }

    func persistMood(_ mood: MoodLog) async -> Bool {
        careRevision += 1
        operationError = nil
        let normalized = mood.normalized()
        do {
            try await dependencies.careStore.saveMood(normalized)
            apply(try await dependencies.careStore.snapshot())
            if !moods.contains(where: { $0.id == normalized.id }) {
                Self.upsert(normalized, in: &moods)
            }
            currentMoodID = normalized.id
            refreshLoadState()
            dependencies.logger.record(.moodSaved, metrics: EventMetrics(count: 1))
            return true
        } catch {
            operationError = UserFacingError.saving.message
            return false
        }
    }

    func createJournal(rawText: String, inputType: JournalEntry.InputType = .text, attachmentID: UUID? = nil) async -> JournalEntry? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || (inputType != .text && attachmentID != nil) else { return nil }
        let now = dependencies.now()
        let title = trimmed.isEmpty ? (inputType == .voice ? "Voice journal" : "Photo journal") : Self.fallbackTitle(for: trimmed)
        let entry = JournalEntry(
            id: UUID(), createdAt: now, updatedAt: now, inputType: inputType,
            title: title, rawText: rawText, cleanedText: nil,
            summaryItems: [], originalAttachmentID: attachmentID,
            audioAttachmentID: inputType == .voice ? attachmentID : nil, moodLogID: nil,
            pinnedForNextAppointment: false, processingStatus: .unprocessed,
            provenance: Provenance(voice: .user, label: "You saved this", detail: "Saved on this device", occurredAt: now, sourceRoute: .journalDetail)
        )
        guard await saveJournal(entry) else { return nil }
        return entry
    }

    func saveJournal(_ entry: JournalEntry) async -> Bool {
        careRevision += 1
        operationError = nil
        do {
            try await dependencies.careStore.saveJournal(entry)
            Self.upsert(entry, in: &journals)
            refreshLoadState()
            dependencies.logger.record(.journalSaved, metrics: EventMetrics(count: 1))
            return true
        } catch {
            operationError = UserFacingError.saving.message
            return false
        }
    }

    func editJournal(id: UUID, rawText: String) async -> Bool {
        guard let index = journals.firstIndex(where: { $0.id == id }) else { return false }
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var edited = journals[index]
        edited.rawText = rawText
        edited.updatedAt = dependencies.now()
        edited.title = Self.fallbackTitle(for: trimmed)
        return await saveJournal(edited)
    }

    func deleteJournal(id: UUID) async -> Bool {
        careRevision += 1
        operationError = nil
        do {
            try await dependencies.careStore.deleteJournal(id: id)
            journals.removeAll { $0.id == id }
            refreshLoadState()
            return true
        } catch {
            operationError = UserFacingError.saving.message
            return false
        }
    }

    func saveAppointment(_ appointment: Appointment) async -> Bool {
        careRevision += 1
        operationError = nil
        do {
            try await dependencies.careStore.saveAppointment(appointment)
            Self.upsert(appointment, in: &appointments)
            refreshLoadState()
            return true
        } catch {
            operationError = UserFacingError.saving.message
            return false
        }
    }

    @discardableResult
    func addGoal(_ goal: Goal) -> Bool {
        guard !goals.contains(where: { $0.id == goal.id }) else { return false }
        goals.append(goal)
        return true
    }

    func saveGoal(_ goal: Goal) async -> Bool {
        careRevision += 1
        operationError = nil
        do {
            try await dependencies.careStore.saveGoal(goal)
            Self.upsert(goal, in: &goals)
            refreshLoadState()
            return true
        } catch {
            operationError = UserFacingError.saving.message
            return false
        }
    }

    func transitionGoal(id: UUID, to status: Goal.Status) async -> Bool {
        guard !busyGoalIDs.contains(id),
              let goal = goals.first(where: { $0.id == id }), goal.status != status else { return false }
        busyGoalIDs.insert(id)
        defer { busyGoalIDs.remove(id) }
        var updated = goal
        updated.status = status
        guard await saveGoal(updated) else { return false }
        if status == .completed, !goalProgress.contains(where: { $0.goalID == id && $0.source == .userConfirmed }) {
            let progress = GoalProgress(id: UUID(), goalID: id, sourceEntryID: nil, note: "Marked complete", source: .userConfirmed, createdAt: dependencies.now())
            do {
                try await dependencies.careStore.addGoalProgress(progress)
                goalProgress.append(progress)
            } catch {
                operationError = UserFacingError.saving.message
                try? await dependencies.careStore.saveGoal(goal)
                Self.upsert(goal, in: &goals)
                return false
            }
        }
        return true
    }

    func toggleGoal(id: UUID) {
        guard let index = goals.firstIndex(where: { $0.id == id }) else { return }
        careRevision += 1
        goals[index].status = goals[index].status == .completed ? .active : .completed
    }

    @discardableResult
    func addTalkingPoint(_ point: TalkingPoint) -> Bool {
        guard !talkingPoints.contains(where: { $0.id == point.id }) else { return false }
        talkingPoints.append(point)
        return true
    }

    func saveTalkingPoint(_ point: TalkingPoint) async -> Bool {
        careRevision += 1
        operationError = nil
        do {
            try await dependencies.careStore.saveTalkingPoint(point)
            Self.upsert(point, in: &talkingPoints)
            refreshLoadState()
            return true
        } catch {
            operationError = UserFacingError.saving.message
            return false
        }
    }

    func createTalkingPoint(
        text: String,
        source: TalkingPoint.Source = .manual,
        sourceID: UUID? = nil,
        targetAppointmentKind: Appointment.Kind = .therapy
    ) async -> TalkingPoint? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let point = TalkingPoint(
            id: UUID(), text: trimmed, source: source, sourceID: sourceID,
            targetAppointmentKind: targetAppointmentKind, isImportant: false, status: .open,
            createdAt: dependencies.now(),
            provenance: Provenance(voice: .user, label: "You added this", detail: "For the next appointment", occurredAt: dependencies.now(), sourceRoute: .bringUp)
        )
        return await saveTalkingPoint(point) ? point : nil
    }

    func updateTalkingPoint(id: UUID, status: TalkingPoint.Status) {
        guard let index = talkingPoints.firstIndex(where: { $0.id == id }) else { return }
        careRevision += 1
        talkingPoints[index].status = status
    }

    func transitionTalkingPoint(id: UUID, to status: TalkingPoint.Status) async -> Bool {
        guard !busyTalkingPointIDs.contains(id),
              let point = talkingPoints.first(where: { $0.id == id }), point.status != status else { return false }
        busyTalkingPointIDs.insert(id)
        defer { busyTalkingPointIDs.remove(id) }
        var updated = point
        updated.status = status
        return await saveTalkingPoint(updated)
    }

    func search(_ query: String) async {
        let bounded = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        searchGeneration += 1
        let generation = searchGeneration
        guard !bounded.isEmpty else {
            searchResults = []
            searchState = .empty
            return
        }
        searchState = .loading
        do {
            let results = try await dependencies.careStore.search(bounded, limit: 50)
            guard generation == searchGeneration else { return }
            searchResults = results
            searchState = results.isEmpty ? .empty : .loaded
            dependencies.logger.record(.searchCompleted, metrics: EventMetrics(count: results.count))
        } catch {
            guard generation == searchGeneration else { return }
            searchState = .failed("Search is unavailable right now.")
        }
    }

    func setSampleContentEnabled(_ enabled: Bool) async -> Bool {
        careRevision += 1
        operationError = nil
        do {
            try await dependencies.careStore.setSampleContentEnabled(enabled)
            apply(try await dependencies.careStore.snapshot())
            refreshLoadState()
            return true
        } catch {
            operationError = UserFacingError.saving.message
            return false
        }
    }

    func updateSettings(_ updated: VaultSettings) async -> Bool {
        aiSettingsRevision += 1
        operationError = nil
        var normalized = updated
        if normalized.aiMode == .off {
            normalized.aiProvider = .off
        }
        do {
            try await dependencies.careStore.updateSettings(normalized)
            settings = normalized
            return true
        } catch {
            operationError = UserFacingError.saving.message
            return false
        }
    }

    func startRecording(kind: RecordingKind) async -> Bool {
        guard activeRecordingKind == nil else { return false }
        operationError = nil
        let status = await dependencies.recording.authorizationStatus()
        let permitted: Bool
        if status == .authorized {
            permitted = true
        } else if status == .notDetermined {
            permitted = await dependencies.recording.requestPermission()
        } else {
            permitted = false
        }
        guard permitted else {
            operationError = "Microphone access is off. You can enable it in Settings."
            return false
        }
        do {
            try await dependencies.recording.start(kind: kind)
            activeRecordingKind = kind
            recordingSnapshot.isRecording = true
            listenForRecordingEvents()
            dependencies.logger.record(.recordingStarted, metrics: EventMetrics())
            return true
        } catch {
            operationError = UserFacingError.recording.message
            return false
        }
    }

    func stopRecording(reason: RecordingStopReason = .user) async -> LocalRecording? {
        guard let recordingKind = activeRecordingKind else { return nil }
        activeRecordingKind = nil
        do {
            let recording = try await dependencies.recording.stop(reason: reason)
            guard recording.attachment.byteCount > 0 else { throw UserFacingError.recording }
            latestRecording = recording
            recordingSnapshot.isRecording = false
            _ = await persist(recording, kind: recordingKind)
            return recording
        } catch {
            operationError = UserFacingError.recording.message
            return nil
        }
    }

    func savePhotoJPEG(_ data: Data, pixelWidth: Int, pixelHeight: Int) async -> Attachment? {
        careRevision += 1
        operationError = nil
        let status = await dependencies.photos.authorizationStatus()
        let permitted: Bool
        if status == .authorized {
            permitted = true
        } else if status == .notDetermined {
            permitted = await dependencies.photos.requestPermission()
        } else {
            permitted = false
        }
        guard permitted else {
            operationError = "Camera access is off. You can enable it in Settings."
            return nil
        }
        do {
            let attachment = try await dependencies.photos.saveJPEG(data, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
            try await dependencies.careStore.saveAttachment(attachment)
            Self.upsert(attachment, in: &attachments)
            refreshLoadState()
            return attachment
        } catch {
            operationError = UserFacingError.saving.message
            return nil
        }
    }

    func makeExport() async {
        guard exportState != .exporting else { return }
        exportState = .exporting
        do {
            let package = try await dependencies.exporter.makeExport()
            exportState = .ready(package)
            dependencies.logger.record(.exportCompleted, metrics: EventMetrics())
        } catch {
            exportState = .failed(UserFacingError.export.message)
        }
    }

    func cleanupExport() async {
        guard case let .ready(package) = exportState else { return }
        await dependencies.exporter.cleanup(package)
        exportState = .idle
    }

    func deleteEverything(typedText: String) async -> Bool {
        guard let confirmation = DeleteConfirmation(typedText: typedText) else { return false }
        do {
            try await dependencies.exporter.deleteEverything(confirmation: confirmation)
            try dependencies.openRouterKeyStore.removeKey()
            try dependencies.aiConfigurationStore.reset()
            apply(try await dependencies.careStore.snapshot())
            hasOpenRouterKey = false
            routerAvailable = false
            aiConfiguration = .defaults
            aiSettingsRevision += 1
            refreshLoadState()
            exportState = .deleted
            dependencies.logger.record(.vaultDeleted, metrics: EventMetrics())
            return true
        } catch {
            exportState = .failed("Your care vault could not be deleted. Nothing changed.")
            return false
        }
    }

    func setAIMode(_ mode: AIMode) {
        aiSettingsRevision += 1
        settings.aiMode = mode
        if mode == .off {
            settings.aiProvider = .off
        }
    }

    func setAIProvider(_ provider: AIProvider) {
        aiSettingsRevision += 1
        guard settings.aiMode != .off else {
            settings.aiProvider = .off
            return
        }
        switch provider {
        case .router where routerAvailable:
            settings.aiProvider = .router
        case .off:
            settings.aiProvider = .off
        case .router, .onDeviceWhenAvailable:
            settings.aiProvider = .off
        }
    }

    func persistAIMode(_ mode: AIMode) async -> Bool {
        setAIMode(mode)
        return await updateSettings(settings)
    }

    func persistAIProvider(_ provider: AIProvider) async -> Bool {
        setAIProvider(provider)
        return await updateSettings(settings)
    }

    func prepareAISend(_ action: AISendAction) throws -> PendingAISend {
        let payload = try preparedPayload(for: action)
        let disclosure = Self.disclosure(for: action, payload: payload)
        let pending = PendingAISend(
            id: UUID(),
            action: action,
            sourceRevision: payload.sourceRevision,
            disclosure: disclosure
        )
        storePreparedSend(PreparedAIContext(
            pending: pending,
            payload: payload,
            careRevision: careRevision
        ))
        aiProcessingStates[action] = .idle
        return pending
    }

    func prepareProcessedSessionSummary(appointmentID: UUID) throws -> PendingAISend {
        try prepareAISend(.summarizeProcessedSession(appointmentID))
    }

    /// Retrieves the bounded, source-attributed vault context used by Prepare.
    func appointmentContextPacket(
        kind: Appointment.Kind,
        window: DateInterval
    ) async throws -> ContextPacket {
        let now = dependencies.now()
        guard window.start <= window.end, window.end <= now else { throw UserFacingError.aiSource }
        let retriever: any MemoryRetrieving = MemoryRetriever(careStore: dependencies.careStore)
        return try await retriever.retrieve(MemoryRetrievalRequest(
            appointmentKind: kind,
            window: window,
            now: now
        ))
    }

    /// Prepares one consent disclosure. No provider request occurs until `performAISend` receives this token.
    func prepareAppointmentBriefSend(
        kind: Appointment.Kind,
        window: DateInterval? = nil
    ) async throws -> PendingAISend {
        if let existing = preparedAppointmentBrief(kind: kind) { return existing }
        let revision = careRevision
        let now = dependencies.now()
        let resolvedWindow = window ?? DateInterval(
            start: now.addingTimeInterval(-90 * 24 * 60 * 60),
            end: now
        )
        let packet = try await retrieveAppointmentBriefPacket(
            kind: kind,
            window: resolvedWindow,
            now: now,
            revision: revision
        )
        try Task.checkCancellation()
        guard revision == careRevision else { throw UserFacingError.aiStale }
        if let existing = preparedAppointmentBrief(kind: kind) { return existing }
        return try storeAppointmentBriefSend(kind: kind, packet: packet, revision: revision)
    }

    private func retrieveAppointmentBriefPacket(
        kind: Appointment.Kind,
        window: DateInterval,
        now: Date,
        revision: Int
    ) async throws -> ContextPacket {
        let preparation: AppointmentBriefPreparation
        if let active = appointmentBriefPreparations[kind], active.careRevision == revision {
            preparation = active
        } else {
            appointmentBriefPreparations[kind]?.task.cancel()
            let retriever: any MemoryRetrieving = MemoryRetriever(careStore: dependencies.careStore)
            let request = MemoryRetrievalRequest(appointmentKind: kind, window: window, now: now)
            preparation = AppointmentBriefPreparation(
                id: UUID(),
                careRevision: revision,
                task: Task { try await retriever.retrieve(request) }
            )
            appointmentBriefPreparations[kind] = preparation
        }
        defer {
            if appointmentBriefPreparations[kind]?.id == preparation.id {
                appointmentBriefPreparations[kind] = nil
            }
        }
        return try await preparation.task.value
    }

    private func storeAppointmentBriefSend(
        kind: Appointment.Kind,
        packet: ContextPacket,
        revision: Int
    ) throws -> PendingAISend {
        guard !packet.items.isEmpty, !packet.text.isEmpty,
              packet.text.count <= ContextPacketLimits.appointment.maximumCharacters,
              let descriptorID = packet.items.first?.id else {
            throw UserFacingError.aiSource
        }
        let input = AppointmentBriefInput(appointmentKind: kind, contextPacket: packet)
        let action = AISendAction.generateAppointmentBrief(kind)
        let descriptor = OutgoingSourceDescriptor(
            id: descriptorID,
            kind: .text,
            title: "\(kind.displayName) context packet",
            characterCount: packet.text.count,
            imageCount: 0
        )
        let pending = PendingAISend(
            id: UUID(),
            action: action,
            sourceRevision: packet.items.compactMap(\.occurredAt).max(),
            disclosure: WhatLeavesDeviceSummary(
                purpose: Self.purpose(for: action),
                destination: "OpenRouter",
                sources: [descriptor],
                totalCharacterCount: packet.text.count,
                totalImageCount: 0,
                omittedSourceCount: packet.omittedItemCount
            )
        )
        storePreparedSend(PreparedAIContext(
            pending: pending,
            payload: .brief(input, packet.omittedItemCount, .contextPacket),
            careRevision: revision
        ))
        preparedAppointmentBriefIDs[kind] = pending.id
        aiProcessingStates[action] = .idle
        return pending
    }

    /// Prepares a consent disclosure for evidence-backed goal progress suggestions without contacting a provider.
    func prepareGoalProgressSuggestions(
        from source: GoalProgressSuggestionSource
    ) async throws -> PendingAISend {
        if let existing = preparedGoalProgress(source: source) { return existing }
        let revision = careRevision
        let suggester = GoalProgressSuggester(
            careStore: dependencies.careStore,
            languageModel: dependencies.languageModel,
            now: dependencies.now
        )
        let input: GoalProgressSuggestionInput
        do {
            input = try await suggester.prepareInput(from: source)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw UserFacingError.aiSource
        }
        try Task.checkCancellation()
        guard revision == careRevision else { throw UserFacingError.aiStale }
        if let existing = preparedGoalProgress(source: source) { return existing }
        let action = AISendAction.suggestGoalProgress(source)
        let pending = PendingAISend(
            id: UUID(),
            action: action,
            sourceRevision: input.sources.compactMap(\.document.occurredAt).max(),
            disclosure: WhatLeavesDeviceSummary(
                purpose: "Suggest goal progress",
                destination: "OpenRouter",
                sources: [OutgoingSourceDescriptor(
                    id: input.originID,
                    kind: .text,
                    title: "Goal progress source and active goals",
                    characterCount: input.requestText.count,
                    imageCount: 0
                )],
                totalCharacterCount: input.requestText.count,
                totalImageCount: 0,
                omittedSourceCount: 0
            )
        )
        storePreparedSend(PreparedAIContext(pending: pending, payload: .goalProgress(input), careRevision: revision))
        preparedGoalProgressIDs[source] = pending.id
        aiProcessingStates[action] = .idle
        return pending
    }

    /// Prepares the current week's consent disclosure only. Present it, then call `performAISend` after the user taps Send.
    func refreshWeeklySummary() async throws -> PendingAISend? {
        let now = dependencies.now()
        let interval = try WeeklyConsolidator.weekInterval(containing: now, calendar: .autoupdatingCurrent)
        if currentWeeklySummary != nil { return nil }
        guard canDispatchAI() else { throw UserFacingError.aiUnavailable }
        if let existing = preparedWeeklySummary(weekStart: interval.start) { return existing }
        let revision = careRevision
        let consolidator = WeeklyConsolidator(
            careStore: dependencies.careStore,
            languageModel: dependencies.languageModel,
            calendar: .autoupdatingCurrent,
            now: dependencies.now
        )
        let preparation: WeeklySummaryPreparation?
        do {
            preparation = try await consolidator.prepareSummary(for: now)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw UserFacingError.aiSource
        }
        try Task.checkCancellation()
        guard revision == careRevision else { throw UserFacingError.aiStale }
        guard let preparation else { return nil }
        if currentWeeklySummary != nil { return nil }
        if let existing = preparedWeeklySummary(weekStart: interval.start) { return existing }
        guard let firstSource = preparation.input.sources.first else { return nil }
        let action = AISendAction.generateWeeklySummary(interval.start)
        let pending = PendingAISend(
            id: UUID(),
            action: action,
            sourceRevision: preparation.input.sources.compactMap(\.document.occurredAt).max(),
            disclosure: WhatLeavesDeviceSummary(
                purpose: "Create this weekly summary",
                destination: "OpenRouter",
                sources: [OutgoingSourceDescriptor(
                    id: firstSource.id,
                    kind: .text,
                    title: "Weekly vault context",
                    characterCount: preparation.input.requestText.count,
                    imageCount: 0
                )],
                totalCharacterCount: preparation.input.requestText.count,
                totalImageCount: 0,
                omittedSourceCount: preparation.omittedSourceCount
            )
        )
        storePreparedSend(PreparedAIContext(
            pending: pending,
            payload: .weeklySummary(preparation.input),
            careRevision: revision
        ))
        preparedWeeklySummaryIDs[interval.start] = pending.id
        aiProcessingStates[action] = .idle
        return pending
    }

    @discardableResult
    func accept(suggestionID: UUID) async -> Bool {
        await resolveProgressSuggestion(id: suggestionID, as: .accepted)
    }

    @discardableResult
    func dismiss(suggestionID: UUID) async -> Bool {
        await resolveProgressSuggestion(id: suggestionID, as: .dismissed)
    }

    private func resolveProgressSuggestion(
        id: UUID,
        as resolution: GoalProgressSuggestionResolution
    ) async -> Bool {
        guard !busyProgressSuggestionIDs.contains(id) else { return false }
        busyProgressSuggestionIDs.insert(id)
        defer { busyProgressSuggestionIDs.remove(id) }
        do {
            try await dependencies.careStore.resolveGoalProgressSuggestion(
                id: id,
                as: resolution,
                at: dependencies.now()
            )
            apply(try await dependencies.careStore.snapshot())
            refreshLoadState()
            operationError = nil
            return true
        } catch {
            operationError = UserFacingError.saving.message
            return false
        }
    }

    @discardableResult
    func performAISend(_ pending: PendingAISend) async -> Bool {
        guard let prepared = consumePreparedSend(pending.id), prepared.pending == pending else {
            return failAI(pending.action, UserFacingError.aiSource)
        }
        guard !activeAISends.contains(pending.action) else { return false }
        guard canDispatchAI(), prepared.careRevision == careRevision else {
            let error = prepared.careRevision == careRevision ? UserFacingError.aiUnavailable : UserFacingError.aiStale
            return failAI(pending.action, error)
        }
        let settingsRevision = aiSettingsRevision
        let configuration = aiConfiguration
        activeAISends.insert(pending.action)
        aiProcessingStates[pending.action] = .processing
        defer { activeAISends.remove(pending.action) }
        do {
            if case .summarizeProcessedSession = pending.action {
                try ensureCurrent(prepared, settingsRevision: settingsRevision, configuration: configuration)
                guard case let .processedSession(context) = prepared.payload else {
                    throw AIProviderError.invalidInput
                }
                try await dependencies.sessionProcessing.noteSummaryStarted(appointmentID: context.appointment.id)
                apply(try await dependencies.careStore.snapshot())
                guard sessionProcessingRecord(for: context.appointment.id)?.stage == .ready else {
                    let message = sessionProcessingRecord(for: context.appointment.id)?.failure?.message
                        ?? "The debrief could not be created. The recording and transcript are unchanged."
                    throw UserFacingError(message: message)
                }
                aiProcessingStates[pending.action] = .succeeded
                operationError = nil
                return true
            }
            let product = try await run(prepared.payload, action: pending.action)
            try ensureCurrent(prepared, settingsRevision: settingsRevision, configuration: configuration)
            try await dependencies.organizer.persist(product)
            do {
                try ensureCurrent(prepared, settingsRevision: settingsRevision, configuration: configuration)
            } catch {
                try? await dependencies.organizer.deleteArtifact(id: product.artifact.id)
                throw error
            }
            try await commit(product, payload: prepared.payload)
            aiProcessingStates[pending.action] = .succeeded
            operationError = nil
            return true
        } catch is CancellationError {
            return failAI(pending.action, UserFacingError.aiCanceled)
        } catch let error as UserFacingError {
            return failAI(pending.action, error)
        } catch let error as AIProviderError {
            return failAI(pending.action, UserFacingError(message: error.userMessage))
        } catch {
            return failAI(pending.action, UserFacingError(message: AIProviderError.serviceUnavailable.userMessage))
        }
    }

    func aiProcessingState(for action: AISendAction) -> AIProcessingState {
        aiProcessingStates[action] ?? .idle
    }

    @discardableResult
    func storeOpenRouterKey(_ value: String) -> Bool {
        do {
            try dependencies.openRouterKeyStore.storeKey(value)
            hasOpenRouterKey = try dependencies.openRouterKeyStore.hasKey()
            routerAvailable = hasOpenRouterKey
            aiSettingsRevision += 1
            operationError = nil
            return hasOpenRouterKey
        } catch {
            operationError = "That router key could not be saved. Check it and try again."
            return false
        }
    }

    @discardableResult
    func removeOpenRouterKey() async -> Bool {
        do {
            try dependencies.openRouterKeyStore.removeKey()
            hasOpenRouterKey = false
            routerAvailable = false
            aiSettingsRevision += 1
            if settings.aiProvider == .router {
                settings.aiProvider = .off
                try await dependencies.careStore.updateSettings(settings)
            }
            operationError = nil
            return true
        } catch {
            operationError = "The router key could not be removed. Try again."
            return false
        }
    }

    @discardableResult
    func updateAIConfiguration(_ configuration: AIModelConfiguration) -> Bool {
        do {
            try dependencies.aiConfigurationStore.save(configuration)
            aiConfiguration = dependencies.aiConfigurationStore.load()
            aiSettingsRevision += 1
            operationError = nil
            return true
        } catch {
            operationError = "Those model settings could not be saved."
            return false
        }
    }

    func latestArtifact(kind: AIArtifact.Kind, sourceID: UUID) -> AIArtifact? {
        artifacts
            .filter { $0.kind == kind && $0.sourceIDs.contains(sourceID) }
            .max { $0.createdAt < $1.createdAt }
    }

    func sessionProcessingRecord(for appointmentID: UUID) -> SessionProcessingRecord? {
        sessionProcessing.first { $0.appointmentID == appointmentID }
    }

    func structuredSessionSummary(
        for appointmentID: UUID
    ) -> (artifact: AIArtifact, result: StructuredSessionSummaryResult)? {
        guard let appointment = appointments.first(where: { $0.id == appointmentID }),
              let summaryID = appointment.summaryID,
              let artifact = artifacts.first(where: { $0.id == summaryID && $0.kind == .sessionSummary }),
              let result = try? JSONDecoder().decode(StructuredSessionSummaryResult.self, from: artifact.structuredPayload),
              result.debriefTopics.count >= 3, result.debriefTopics.count <= 5 else { return nil }
        return (artifact, result)
    }

    func beginOrResumeSessionProcessing(appointmentID: UUID) async {
        await dependencies.sessionProcessing.beginOrResume(appointmentID: appointmentID)
        await refreshPhase4Snapshot()
    }

    func retrySessionProcessing(appointmentID: UUID) async {
        await dependencies.sessionProcessing.retry(appointmentID: appointmentID)
        await refreshPhase4Snapshot()
    }

    func persistSpeakerCluster(
        segmentID: UUID,
        as speaker: TranscriptSegment.Speaker,
        rememberPatientVoice: Bool = false
    ) async -> Bool {
        guard speaker != .unknown,
              let segment = transcript.first(where: { $0.id == segmentID }),
              let label = segment.rawSpeakerLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty else { return false }
        let key = "\(segment.appointmentID.uuidString):\(label)"
        guard !busySpeakerClusters.contains(key) else { return false }
        busySpeakerClusters.insert(key)
        defer { busySpeakerClusters.remove(key) }
        let existing = speakerAssignments.first {
            $0.appointmentID == segment.appointmentID && $0.rawSpeakerLabel == label
        }
        let assignment = SpeakerClusterAssignment(
            id: existing?.id ?? UUID(), appointmentID: segment.appointmentID,
            rawSpeakerLabel: label, speaker: speaker, updatedAt: dependencies.now()
        )
        do {
            try await dependencies.careStore.assignSpeakerCluster(
                assignment, rememberPatientVoice: rememberPatientVoice
            )
            apply(try await dependencies.careStore.snapshot())
            operationError = nil
            return true
        } catch {
            operationError = "That speaker label could not be saved. The transcript is unchanged."
            return false
        }
    }

    func applyDebriefMutation(_ mutation: SessionDebriefMutation) async -> Bool {
        do {
            try await dependencies.careStore.applySessionDebriefMutation(mutation)
            apply(try await dependencies.careStore.snapshot())
            operationError = nil
            return true
        } catch {
            operationError = "That debrief choice could not be saved. Your session is unchanged."
            return false
        }
    }

    func playSessionRecording(appointmentID: UUID, fromMilliseconds: Int) async -> Bool {
        guard fromMilliseconds >= 0,
              let appointment = appointments.first(where: { $0.id == appointmentID }),
              let attachmentID = appointment.recordingAttachmentID,
              let attachment = attachments.first(where: { $0.id == attachmentID }) else { return false }
        do {
            try await dependencies.playback.play(
                attachment: attachment, fromMilliseconds: fromMilliseconds
            )
            operationError = nil
            return true
        } catch {
            operationError = UserFacingError.playback.message
            return false
        }
    }

    @discardableResult
    func saveEditedAppointmentBrief(_ artifactID: UUID, result: AppointmentBriefResult) async -> Bool {
        guard let existing = artifacts.first(where: { $0.id == artifactID && $0.kind == .appointmentBrief }) else {
            return false
        }
        let edited = AppointmentBriefResult(
            sections: result.sections,
            userEditedAt: result.userEditedAt ?? dependencies.now(),
            metadata: AIResultMetadata(
                provider: existing.provider,
                model: existing.model,
                usage: result.metadata.usage
            )
        )
        do {
            let payload = try Self.encode(edited)
            let replacement = AIArtifact(
                id: existing.id,
                kind: existing.kind,
                sourceIDs: existing.sourceIDs,
                provider: existing.provider,
                model: existing.model,
                structuredPayload: payload,
                createdAt: existing.createdAt
            )
            try await dependencies.organizer.replaceArtifact(replacement)
            Self.upsert(replacement, in: &artifacts)
            return true
        } catch {
            operationError = UserFacingError.saving.message
            return false
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
        guard durationSeconds >= 0, case .recording = appointmentRecording else { return false }
        appointmentRecording = .saved(durationSeconds: durationSeconds)
        return true
    }

    @discardableResult
    func correctSpeaker(segmentID: UUID, to speaker: TranscriptSegment.Speaker) -> Bool {
        guard speaker != .unknown,
              let segment = transcript.first(where: { $0.id == segmentID }),
              segment.speaker == .unknown,
              speakerCorrections[segmentID] == nil else { return false }
        speakerCorrections[segmentID] = speaker
        return true
    }

    func reset() {
        apply(SeededData.careSnapshot)
        speakerCorrections = [:]
        hasOpenRouterKey = (try? dependencies.openRouterKeyStore.hasKey()) ?? false
        routerAvailable = hasOpenRouterKey
        aiConfiguration = dependencies.aiConfigurationStore.load()
        consentAcknowledged = false
        selectedAppointmentKind = .therapy
        appointmentRecording = .idle
        exportState = .idle
        operationError = nil
        preparedAISends = [:]
        preparedAISendOrder = []
        for preparation in appointmentBriefPreparations.values { preparation.task.cancel() }
        appointmentBriefPreparations = [:]
        preparedAppointmentBriefIDs = [:]
        preparedGoalProgressIDs = [:]
        preparedWeeklySummaryIDs = [:]
        activeAISends = []
        aiProcessingStates = [:]
    }

    func clearError() { operationError = nil }

    func selectJournal(id: UUID) { selectedJournalID = id }
    func selectAppointment(id: UUID) { selectedAppointmentID = id }

    private func preparedPayload(for action: AISendAction) throws -> PreparedAIPayload {
        switch action {
        case let .rewriteJournal(id), let .summarizeJournal(id), let .extractJournalSignals(id):
            guard let journal = journals.first(where: { $0.id == id }) else { throw UserFacingError.aiSource }
            return .journal(journal, try journalSource(journal))
        case let .readPhoto(journalID, attachmentID):
            guard let journal = journals.first(where: { $0.id == journalID }),
                  journal.inputType == .photo,
                  journal.originalAttachmentID == attachmentID,
                  let attachment = attachments.first(where: { $0.id == attachmentID && $0.kind == .image }) else {
                throw UserFacingError.aiSource
            }
            return .photo(journal, attachment)
        case let .summarizeSession(id):
            guard let appointment = appointments.first(where: { $0.id == id }) else { throw UserFacingError.aiSource }
            let notes = appointment.manualNotes
            guard !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw UserFacingError.aiSource }
            return .session(appointment, SourceTextDocument(
                id: appointment.id,
                kind: .sessionNotes,
                title: "Manual notes from \(appointment.kind.displayName.lowercased())",
                text: notes,
                occurredAt: appointment.endedAt ?? appointment.startedAt ?? appointment.scheduledAt
            ))
        case let .summarizeProcessedSession(id):
            guard let appointment = appointments.first(where: { $0.id == id }),
                  let attachmentID = appointment.recordingAttachmentID else { throw UserFacingError.aiSource }
            let segments = transcript.filter { $0.appointmentID == id }
                .sorted { ($0.startMilliseconds, $0.id.uuidString) < ($1.startMilliseconds, $1.id.uuidString) }
            guard !segments.isEmpty else { throw UserFacingError.aiSource }
            return .processedSession(ProcessedSessionAIContext(
                appointment: appointment,
                attachmentID: attachmentID,
                transcript: segments.map {
                    SessionTranscriptSource(
                        id: $0.id, speaker: $0.speaker, rawSpeakerLabel: $0.rawSpeakerLabel,
                        startMilliseconds: $0.startMilliseconds, endMilliseconds: $0.endMilliseconds,
                        text: $0.text
                    )
                },
                talkingPoints: talkingPoints.filter {
                    $0.status == .open && $0.targetAppointmentKind == appointment.kind
                }.prefix(64).map { SessionTalkingPointSource(id: $0.id, text: $0.text) }
            ))
        case let .generateAppointmentBrief(kind):
            return try briefPayload(kind: kind)
        }
    }

    private func journalSource(_ journal: JournalEntry) throws -> SourceTextDocument {
        if journal.inputType == .photo {
            guard let artifact = latestArtifact(kind: .photoText, sourceID: journal.id),
                  let result = try? JSONDecoder().decode(VisionReadResult.self, from: artifact.structuredPayload),
                  !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw UserFacingError.aiSource
            }
            return SourceTextDocument(
                id: artifact.id,
                kind: .extractedPhotoText,
                title: "Extracted text from (journal.title)",
                text: result.text,
                occurredAt: artifact.createdAt
            )
        }
        guard !journal.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UserFacingError.aiSource
        }
        return SourceTextDocument(
            id: journal.id,
            kind: .journal,
            title: journal.title,
            text: journal.rawText,
            occurredAt: journal.createdAt
        )
    }

    private func briefPayload(kind: Appointment.Kind) throws -> PreparedAIPayload {
        guard journals.count <= 100_000, moods.count <= 100_000, appointments.count <= 100_000,
              goals.count <= 100_000, talkingPoints.count <= 100_000 else {
            throw UserFacingError.aiSelectionTooLarge
        }
        let lastSession = latestCompletedAppointment(kind: kind)
        let boundary = lastSession.flatMap { $0.endedAt ?? $0.startedAt ?? $0.scheduledAt }
        var required = requiredBriefSources(kind: kind, lastSession: lastSession, boundary: boundary)
        let requiredCount = required.reduce(0) { $0 + $1.text.count }
        guard requiredCount <= 50_000, required.count <= 64 else { throw UserFacingError.aiSelectionTooLarge }
        var total = requiredCount
        var omitted = 0
        let recentJournals = journals
            .filter { journal in boundary.map { journal.createdAt > $0 } ?? true }
            .sorted { $0.createdAt > $1.createdAt }
        for journal in recentJournals {
            guard let source = try? journalSource(journal) else {
                omitted += 1
                continue
            }
            guard required.count < 64, total + source.text.count <= 50_000 else {
                omitted += 1
                continue
            }
            required.append(source)
            total += source.text.count
        }
        guard !required.isEmpty else { throw UserFacingError.aiSource }
        return .brief(AppointmentBriefInput(appointmentKind: kind, sources: required), omitted, .individualSources)
    }

    private func requiredBriefSources(
        kind: Appointment.Kind,
        lastSession: Appointment?,
        boundary: Date?
    ) -> [SourceTextDocument] {
        var sources: [SourceTextDocument] = []
        if let lastSession, !lastSession.manualNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sources.append(sessionSource(lastSession))
        }
        for goal in goals where isProviderHomework(goal, kind: kind) {
            sources.append(goalSource(goal, kind: .homework, titlePrefix: "Provider homework"))
        }
        for goal in goals where goal.status == .active && !isProviderHomework(goal, kind: kind) {
            sources.append(goalSource(goal, kind: .goal, titlePrefix: "Active goal"))
        }
        for point in talkingPoints where point.status == .open && point.targetAppointmentKind == kind {
            sources.append(SourceTextDocument(
                id: point.id, kind: .talkingPoint, title: "Pinned item", text: point.text, occurredAt: point.createdAt
            ))
        }
        if let mood = moodTrendSource(boundary: boundary) { sources.append(mood) }
        return sources
    }

    private func latestCompletedAppointment(kind: Appointment.Kind) -> Appointment? {
        appointments
            .filter { $0.kind == kind && $0.status == .completed }
            .max { appointmentDate($0) < appointmentDate($1) }
    }

    private func isProviderHomework(_ goal: Goal, kind: Appointment.Kind) -> Bool {
        guard goal.source == .providerExplicit, goal.cadence == .homework, goal.status != .dismissed else { return false }
        guard let sourceID = goal.sourceEntityID,
              let appointment = appointments.first(where: { $0.id == sourceID }) else { return true }
        return appointment.kind == kind
    }

    private func sessionSource(_ appointment: Appointment) -> SourceTextDocument {
        SourceTextDocument(
            id: appointment.id,
            kind: .sessionNotes,
            title: "Last \(appointment.kind.displayName.lowercased()) session notes",
            text: appointment.manualNotes,
            occurredAt: appointmentDate(appointment)
        )
    }

    private func goalSource(_ goal: Goal, kind: SourceTextDocument.Kind, titlePrefix: String) -> SourceTextDocument {
        let text = goal.detail.map { "\(goal.title)\n\($0)" } ?? goal.title
        return SourceTextDocument(
            id: goal.id, kind: kind, title: "\(titlePrefix): \(goal.title)", text: text, occurredAt: goal.createdAt
        )
    }

    private func moodTrendSource(boundary: Date?) -> SourceTextDocument? {
        let selected = moods
            .filter { mood in boundary.map { mood.createdAt > $0 } ?? true }
            .sorted { $0.createdAt < $1.createdAt }
        guard let latest = selected.last else { return nil }
        let lines = selected.map(Self.moodTrendLine)
        return SourceTextDocument(
            id: latest.id,
            kind: .moodTrend,
            title: "Mood trend since the last appointment",
            text: lines.joined(separator: "\n"),
            occurredAt: latest.createdAt
        )
    }

    private static func moodTrendLine(_ mood: MoodLog) -> String {
        var fields = ["Date \(dayString(mood.createdAt))"]
        if let value = mood.mood { fields.append("mood \(value)/10") }
        if let value = mood.anxiety { fields.append("anxiety \(value)/10") }
        if let value = mood.energy { fields.append("energy \(value)/10") }
        for key in mood.customValues.keys.sorted() {
            if let value = mood.customValues[key] { fields.append("\(key) \(value)/10") }
        }
        if let note = mood.note, !note.isEmpty { fields.append("note: \(note)") }
        return fields.joined(separator: ", ")
    }

    private static func dayString(_ date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let zone = TimeZone(secondsFromGMT: 0) ?? .current
        let parts = calendar.dateComponents(in: zone, from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func appointmentDate(_ appointment: Appointment) -> Date {
        appointment.endedAt ?? appointment.startedAt ?? appointment.scheduledAt ?? .distantPast
    }

    private static func disclosure(
        for action: AISendAction,
        payload: PreparedAIPayload
    ) -> WhatLeavesDeviceSummary {
        let sources: [OutgoingSourceDescriptor]
        let omitted: Int
        switch payload {
        case let .journal(_, source):
            sources = [textDescriptor(source)]
            omitted = 0
        case let .photo(journal, attachment):
            sources = [OutgoingSourceDescriptor(
                id: attachment.id,
                kind: .image,
                title: "Photo from \(journal.title)",
                characterCount: 0,
                imageCount: 1
            )]
            omitted = 0
        case let .session(_, source):
            sources = [textDescriptor(source)]
            omitted = 0
        case let .brief(input, omittedCount, disclosureStyle):
            if disclosureStyle == .contextPacket, let first = input.contextPacket.items.first {
                sources = [OutgoingSourceDescriptor(
                    id: first.id,
                    kind: .text,
                    title: "\(input.appointmentKind.displayName) context packet",
                    characterCount: input.contextPacket.text.count,
                    imageCount: 0
                )]
            } else {
                sources = input.sources.map(textDescriptor)
            }
            omitted = omittedCount
        case let .processedSession(context):
            sources = context.transcript.map { source in
                OutgoingSourceDescriptor(
                    id: source.id, kind: .text,
                    title: "\(source.speaker.disclosureName) at \(AppointmentRecordingClock.format(milliseconds: source.startMilliseconds))",
                    characterCount: source.text.count, imageCount: 0
                )
            } + context.talkingPoints.map { source in
                OutgoingSourceDescriptor(
                    id: source.id, kind: .text, title: "Open talking point",
                    characterCount: source.text.count, imageCount: 0
                )
            }
            omitted = 0
        case let .goalProgress(input):
            sources = [OutgoingSourceDescriptor(
                id: input.originID,
                kind: .text,
                title: "Goal progress source and active goals",
                characterCount: input.requestText.count,
                imageCount: 0
            )]
            omitted = 0
        case let .weeklySummary(input):
            sources = input.sources.first.map {
                [OutgoingSourceDescriptor(
                    id: $0.id,
                    kind: .text,
                    title: "Weekly vault context",
                    characterCount: input.requestText.count,
                    imageCount: 0
                )]
            } ?? []
            omitted = 0
        }
        return WhatLeavesDeviceSummary(
            purpose: purpose(for: action),
            destination: "OpenRouter",
            sources: sources,
            totalCharacterCount: sources.reduce(0) { $0 + $1.characterCount },
            totalImageCount: sources.reduce(0) { $0 + $1.imageCount },
            omittedSourceCount: omitted
        )
    }

    private static func textDescriptor(_ source: SourceTextDocument) -> OutgoingSourceDescriptor {
        OutgoingSourceDescriptor(
            id: source.id,
            kind: .text,
            title: source.title,
            characterCount: source.text.count,
            imageCount: 0
        )
    }

    private static func purpose(for action: AISendAction) -> String {
        switch action {
        case .rewriteJournal: "Rewrite this journal"
        case .summarizeJournal: "Summarize this journal"
        case .extractJournalSignals: "Find optional journal suggestions"
        case .readPhoto: "Read text from this journal photo"
        case .summarizeSession: "Organize these manual session notes"
        case let .generateAppointmentBrief(kind): "Prepare for \(kind.displayName.lowercased())"
        case .summarizeProcessedSession: "Create this session debrief"
        }
    }

    private func storePreparedSend(_ context: PreparedAIContext) {
        let maximumPreparedSends = 32
        if preparedAISendOrder.count >= maximumPreparedSends {
            let oldest = preparedAISendOrder.removeFirst()
            preparedAISends.removeValue(forKey: oldest)
            preparedAppointmentBriefIDs = preparedAppointmentBriefIDs.filter { $0.value != oldest }
            preparedGoalProgressIDs = preparedGoalProgressIDs.filter { $0.value != oldest }
            preparedWeeklySummaryIDs = preparedWeeklySummaryIDs.filter { $0.value != oldest }
        }
        preparedAISends[context.pending.id] = context
        preparedAISendOrder.append(context.pending.id)
    }

    private func consumePreparedSend(_ id: UUID) -> PreparedAIContext? {
        preparedAISendOrder.removeAll { $0 == id }
        preparedAppointmentBriefIDs = preparedAppointmentBriefIDs.filter { $0.value != id }
        preparedGoalProgressIDs = preparedGoalProgressIDs.filter { $0.value != id }
        preparedWeeklySummaryIDs = preparedWeeklySummaryIDs.filter { $0.value != id }
        return preparedAISends.removeValue(forKey: id)
    }

    private func preparedAppointmentBrief(kind: Appointment.Kind) -> PendingAISend? {
        guard let id = preparedAppointmentBriefIDs[kind],
              let context = preparedAISends[id],
              context.careRevision == careRevision,
              context.pending.action == .generateAppointmentBrief(kind) else {
            preparedAppointmentBriefIDs[kind] = nil
            return nil
        }
        return context.pending
    }

    private func preparedGoalProgress(source: GoalProgressSuggestionSource) -> PendingAISend? {
        guard let id = preparedGoalProgressIDs[source],
              let context = preparedAISends[id],
              context.careRevision == careRevision,
              context.pending.action == .suggestGoalProgress(source) else {
            preparedGoalProgressIDs[source] = nil
            return nil
        }
        return context.pending
    }

    private func preparedWeeklySummary(weekStart: Date) -> PendingAISend? {
        guard let id = preparedWeeklySummaryIDs[weekStart],
              let context = preparedAISends[id],
              context.careRevision == careRevision,
              context.pending.action == .generateWeeklySummary(weekStart) else {
            preparedWeeklySummaryIDs[weekStart] = nil
            return nil
        }
        return context.pending
    }

    private func canDispatchAI() -> Bool {
        guard settings.aiMode == .organizer || settings.aiMode == .reflection,
              settings.aiProvider == .router,
              routerAvailable else { return false }
        let stored = (try? dependencies.openRouterKeyStore.hasKey()) ?? false
        hasOpenRouterKey = stored
        routerAvailable = stored
        return stored
    }

    private func run(_ payload: PreparedAIPayload, action: AISendAction) async throws -> OrganizerWorkProduct {
        switch (action, payload) {
        case (.rewriteJournal, let .journal(_, source)):
            return try await dependencies.organizer.rewriteJournal(source)
        case (.summarizeJournal, let .journal(_, source)):
            return try await dependencies.organizer.summarizeJournal(source)
        case (.extractJournalSignals, let .journal(_, source)):
            return try await dependencies.organizer.extractJournalSignals(source)
        case (.readPhoto, let .photo(journal, attachment)):
            return try await dependencies.organizer.readPhoto(journalID: journal.id, attachment: attachment)
        case (.summarizeSession, let .session(appointment, source)):
            return try await dependencies.organizer.summarizeSession(SessionSummaryInput(
                appointmentID: appointment.id,
                appointmentKind: appointment.kind,
                manualNotes: source
            ))
        case (.generateAppointmentBrief, let .brief(input, _, _)):
            return try await dependencies.organizer.generateAppointmentBrief(input)
        case (.extractJournalSignals, let .goalProgress(input)):
            let product = try await GoalProgressSuggester(
                careStore: dependencies.careStore,
                languageModel: dependencies.languageModel,
                now: dependencies.now
            ).generate(input)
            return OrganizerWorkProduct(artifact: product.artifact, journalMutation: nil)
        case (let weeklyAction, let .weeklySummary(input))
        where weeklyAction == .generateWeeklySummary(input.interval.start):
            let product = try await WeeklyConsolidator(
                careStore: dependencies.careStore,
                languageModel: dependencies.languageModel,
                calendar: .autoupdatingCurrent,
                now: dependencies.now
            ).generate(input)
            return OrganizerWorkProduct(artifact: product.artifact, journalMutation: nil)
        case (.summarizeProcessedSession, .processedSession):
            throw AIProviderError.invalidInput
        default:
            throw AIProviderError.invalidInput
        }
    }

    private func ensureCurrent(
        _ prepared: PreparedAIContext,
        settingsRevision: Int,
        configuration: AIModelConfiguration
    ) throws {
        guard prepared.careRevision == careRevision,
              settingsRevision == aiSettingsRevision,
              configuration == aiConfiguration,
              isPayloadCurrent(prepared.payload),
              canDispatchAI() else {
            throw UserFacingError.aiStale
        }
    }

    private func isPayloadCurrent(_ payload: PreparedAIPayload) -> Bool {
        switch payload {
        case let .journal(journal, source):
            guard journals.first(where: { $0.id == journal.id }) == journal else { return false }
            return (try? journalSource(journal)) == source
        case let .photo(journal, attachment):
            return journals.first(where: { $0.id == journal.id }) == journal
                && attachments.first(where: { $0.id == attachment.id }) == attachment
        case let .session(appointment, source):
            guard appointments.first(where: { $0.id == appointment.id }) == appointment else { return false }
            return appointment.manualNotes == source.text
        case .brief:
            return true
        case let .processedSession(context):
            guard case let .processedSession(current)? = try? preparedPayload(
                for: .summarizeProcessedSession(context.appointment.id)
            ) else { return false }
            return current == context
        case .goalProgress:
            return true
        case .weeklySummary:
            return true
        }
    }

    private func commit(_ product: OrganizerWorkProduct, payload: PreparedAIPayload) async throws {
        Self.upsert(product.artifact, in: &artifacts)
        guard let mutation = product.journalMutation,
              let journalID = payload.journalID,
              let index = journals.firstIndex(where: { $0.id == journalID }) else { return }
        let original = journals[index]
        var updated = original
        switch mutation {
        case let .cleanedText(text): updated.cleanedText = text
        case let .summaryItems(items): updated.summaryItems = items
        }
        updated.processingStatus = .processed
        journals[index] = updated
        do {
            try await dependencies.careStore.saveJournal(updated)
        } catch {
            if let currentIndex = journals.firstIndex(where: { $0.id == journalID }),
               journals[currentIndex] == updated {
                journals[currentIndex] = original
            }
            throw UserFacingError.saving
        }
    }

    private func failAI(_ action: AISendAction, _ error: UserFacingError) -> Bool {
        aiProcessingStates[action] = .failed(error.message)
        operationError = error.message
        return false
    }

    private static func encode<Payload: Encodable>(_ payload: Payload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        guard !data.isEmpty else { throw AIProviderError.invalidResponse }
        return data
    }

    private func apply(_ snapshot: CareSnapshot) {
        careRevision += 1
        journals = snapshot.journals
        moods = snapshot.moods
        appointments = snapshot.appointments
        goals = snapshot.goals
        goalProgress = snapshot.goalProgress
        talkingPoints = snapshot.talkingPoints
        artifacts = snapshot.artifacts
        attachments = snapshot.attachments
        providers = snapshot.providers
        transcript = snapshot.transcript
        sessionProcessing = snapshot.sessionProcessing
        speakerAssignments = snapshot.speakerAssignments
        debriefDecisions = snapshot.debriefDecisions
        settings = snapshot.settings
        if settings.aiMode == .off {
            settings.aiProvider = .off
        }
        currentMoodID = Self.latestMoodID(in: snapshot.moods)
    }

    private static func latestMoodID(in moods: [MoodLog]) -> UUID? {
        moods.max { $0.createdAt < $1.createdAt }?.id
    }

    private var hasCareContent: Bool {
        !journals.isEmpty || !moods.isEmpty || !appointments.isEmpty || !goals.isEmpty
            || !talkingPoints.isEmpty || !attachments.isEmpty || !transcript.isEmpty
    }

    private func refreshLoadState() {
        loadState = hasCareContent ? .loaded : .empty
    }

    private func listenForRecordingEvents() {
        recordingEventsTask?.cancel()
        recordingEventsTask = Task { [weak self, dependencies] in
            for await event in await dependencies.recording.events() {
                guard !Task.isCancelled else { return }
                switch event {
                case let .snapshot(snapshot): self?.recordingSnapshot = snapshot
                case let .stopped(recording):
                    guard let self, let kind = self.activeRecordingKind else { continue }
                    self.activeRecordingKind = nil
                    self.latestRecording = recording
                    self.recordingSnapshot.isRecording = false
                    if await self.persist(recording, kind: kind), kind == .journal {
                        _ = await self.createJournal(rawText: "", inputType: .voice, attachmentID: recording.attachment.id)
                    }
                case let .failed(message): self?.operationError = message
                }
            }
        }
    }

    private func listenForProcessingEvents() {
        guard processingEventsTask == nil else { return }
        processingEventsTask = Task { [weak self, dependencies] in
            for await _ in await dependencies.sessionProcessing.events() {
                guard !Task.isCancelled, let self else { return }
                await self.refreshPhase4Snapshot()
            }
        }
    }

    private func refreshPhase4Snapshot() async {
        guard let snapshot = try? await dependencies.careStore.snapshot() else { return }
        apply(Phase5ScreenshotSeed.applyingIfNeeded(
            to: Phase4ScreenshotSeed.applyingIfNeeded(to: snapshot, arguments: launchArguments),
            arguments: launchArguments, now: dependencies.now()
        ))
        refreshLoadState()
    }

    private func persist(_ recording: LocalRecording, kind: RecordingKind) async -> Bool {
        guard recording.attachment.byteCount > 0 else {
            operationError = UserFacingError.recording.message
            return false
        }
        do {
            try await dependencies.careStore.saveAttachment(recording.attachment)
            Self.upsert(recording.attachment, in: &attachments)
            refreshLoadState()
            if case let .appointment(id) = kind {
                await attach(recording, toAppointment: id)
            }
            dependencies.logger.record(.recordingStopped, metrics: EventMetrics(durationMilliseconds: recording.attachment.durationMilliseconds))
            return true
        } catch {
            operationError = "The recording was saved, but its details could not be updated."
            return false
        }
    }

    private func attach(_ recording: LocalRecording, toAppointment id: UUID) async {
        guard let appointment = appointments.first(where: { $0.id == id }) else { return }
        careRevision += 1
        var updated = appointment
        if updated.recordingAttachmentID != recording.attachment.id {
            updated.transcriptID = nil
            updated.summaryID = nil
        }
        updated.recordingAttachmentID = recording.attachment.id
        updated.endedAt = dependencies.now()
        if updated.startedAt == nil {
            let seconds = TimeInterval(recording.attachment.durationMilliseconds ?? 0) / 1_000
            updated.startedAt = dependencies.now().addingTimeInterval(-seconds)
        }
        updated.status = .processing
        do {
            try await dependencies.careStore.saveAppointment(updated)
            Self.upsert(updated, in: &appointments)
            await beginOrResumeSessionProcessing(appointmentID: id)
        } catch {
            operationError = "The recording was saved, but the appointment details could not be updated."
        }
    }

    private static func upsert<Value: Identifiable>(_ value: Value, in values: inout [Value]) where Value.ID == UUID {
        if let index = values.firstIndex(where: { $0.id == value.id }) {
            values[index] = value
        } else {
            values.append(value)
        }
    }

    private static func fallbackTitle(for text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Journal entry"
        let words = firstLine.split(whereSeparator: \.isWhitespace).prefix(8)
        let title = words.joined(separator: " ")
        return title.isEmpty ? "Journal entry" : title
    }
}

private extension TranscriptSegment.Speaker {
    var disclosureName: String {
        switch self {
        case .patient: "You"
        case .provider: "Provider"
        case .unknown: "Unknown speaker"
        }
    }
}
