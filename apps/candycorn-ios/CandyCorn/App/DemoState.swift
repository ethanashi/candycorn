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
    private(set) var settings: VaultSettings
    private(set) var speakerCorrections: [UUID: TranscriptSegment.Speaker] = [:]
    private(set) var searchResults: [SearchHit] = []
    private(set) var searchState: CareLoadState = .empty
    private(set) var exportState: ExportViewState = .idle
    private(set) var recordingSnapshot = RecordingSnapshot(elapsedMilliseconds: 0, normalizedLevel: 0, isRecording: false)
    private(set) var latestRecording: LocalRecording?
    private(set) var operationError: String?
    private(set) var selectedJournalID: UUID?
    private(set) var selectedAppointmentID: UUID?
    var routerAvailable = true
    var consentAcknowledged = false
    var selectedAppointmentKind: Appointment.Kind = .therapy
    private(set) var appointmentRecording: RecordingDemoStatus = .idle
    private var searchGeneration = 0
    private(set) var activeRecordingKind: RecordingKind?
    private var recordingEventsTask: Task<Void, Never>?
    private var busyGoalIDs: Set<UUID> = []
    private var busyTalkingPointIDs: Set<UUID> = []

    var mood: MoodLog? { moods.max { $0.createdAt < $1.createdAt } }
    var aiMode: AIMode { settings.aiMode }
    var aiProvider: AIProvider { settings.aiProvider }

    init(
        dependencies: AppDependencies? = nil,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        let screenshotMode = Route.parseLaunchArguments(arguments) != nil
        self.dependencies = dependencies ?? PreviewDependencies.make(screenshotMode: screenshotMode)
        let initial = dependencies == nil ? SeededData.careSnapshot : SeededData.emptySnapshot
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
        settings = initial.settings
        if Route.parseLaunchArguments(arguments) == .activeAppointment {
            consentAcknowledged = true
            appointmentRecording = .recording(startSeconds: 0)
        }
    }

    func load() async {
        loadState = .loading
        do {
            apply(try await dependencies.careStore.snapshot())
            refreshLoadState()
            dependencies.logger.record(.vaultOpened, metrics: EventMetrics())
        } catch {
            loadState = .failed(UserFacingError.loading.message)
        }
    }

    func saveMood(_ mood: MoodLog?) {
        guard let mood else {
            moods = []
            return
        }
        Self.upsert(mood.normalized(), in: &moods)
    }

    func persistMood(_ mood: MoodLog) async -> Bool {
        operationError = nil
        do {
            try await dependencies.careStore.saveMood(mood.normalized())
            saveMood(mood)
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
        goals[index].status = goals[index].status == .completed ? .active : .completed
    }

    @discardableResult
    func addTalkingPoint(_ point: TalkingPoint) -> Bool {
        guard !talkingPoints.contains(where: { $0.id == point.id }) else { return false }
        talkingPoints.append(point)
        return true
    }

    func saveTalkingPoint(_ point: TalkingPoint) async -> Bool {
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
        operationError = nil
        do {
            try await dependencies.careStore.updateSettings(updated)
            settings = updated
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
            apply(try await dependencies.careStore.snapshot())
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
        settings.aiMode = mode
        if mode == .off {
            settings.aiProvider = .off
        } else if settings.aiProvider == .off {
            settings.aiProvider = routerAvailable ? .router : .onDeviceWhenAvailable
        }
    }

    func setAIProvider(_ provider: AIProvider) {
        guard settings.aiMode != .off else {
            settings.aiProvider = .off
            return
        }
        settings.aiProvider = provider == .router && !routerAvailable ? .off : provider
    }

    func persistAIMode(_ mode: AIMode) async -> Bool {
        setAIMode(mode)
        return await updateSettings(settings)
    }

    func persistAIProvider(_ provider: AIProvider) async -> Bool {
        setAIProvider(provider)
        return await updateSettings(settings)
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
        routerAvailable = true
        consentAcknowledged = false
        selectedAppointmentKind = .therapy
        appointmentRecording = .idle
        exportState = .idle
        operationError = nil
    }

    func clearError() { operationError = nil }

    func selectJournal(id: UUID) { selectedJournalID = id }
    func selectAppointment(id: UUID) { selectedAppointmentID = id }

    private func apply(_ snapshot: CareSnapshot) {
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
        settings = snapshot.settings
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
        var updated = appointment
        updated.recordingAttachmentID = recording.attachment.id
        updated.endedAt = dependencies.now()
        if updated.startedAt == nil {
            let seconds = TimeInterval(recording.attachment.durationMilliseconds ?? 0) / 1_000
            updated.startedAt = dependencies.now().addingTimeInterval(-seconds)
        }
        updated.status = .completed
        do {
            try await dependencies.careStore.saveAppointment(updated)
            Self.upsert(updated, in: &appointments)
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
