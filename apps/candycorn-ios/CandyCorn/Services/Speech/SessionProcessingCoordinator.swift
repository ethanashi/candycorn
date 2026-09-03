import Foundation

actor SessionProcessingCoordinator: SessionProcessing {
    private static let maximumItems = 100_000

    private let careStore: any CareStore
    private let attachments: any AttachmentStore
    private let transcriber: any CandyCornTranscriber
    private let diarizer: any CandyCornDiarizer
    private let aligner: any TranscriptAligning
    private let summarizer: any CandyCornSessionSummarizer
    private let now: @Sendable () -> Date
    private let eventStream: AsyncStream<SessionProcessingRecord>
    private let eventContinuation: AsyncStream<SessionProcessingRecord>.Continuation
    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    private var runTokens: [UUID: UUID] = [:]

    init(
        careStore: any CareStore,
        attachments: any AttachmentStore,
        transcriber: any CandyCornTranscriber,
        diarizer: any CandyCornDiarizer,
        aligner: any TranscriptAligning = TimestampTranscriptAligner(),
        summarizer: any CandyCornSessionSummarizer,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.careStore = careStore
        self.attachments = attachments
        self.transcriber = transcriber
        self.diarizer = diarizer
        self.aligner = aligner
        self.summarizer = summarizer
        self.now = now
        let pair = AsyncStream.makeStream(
            of: SessionProcessingRecord.self,
            bufferingPolicy: .bufferingNewest(64)
        )
        eventStream = pair.stream
        eventContinuation = pair.continuation
    }

    deinit {
        for task in activeTasks.values.prefix(64) { task.cancel() }
        eventContinuation.finish()
    }

    func status(for appointmentID: UUID) async -> SessionProcessingRecord? {
        try? await careStore.snapshot().sessionProcessing.first { $0.appointmentID == appointmentID }
    }

    func beginOrResume(appointmentID: UUID) async {
        await startAndWait(appointmentID: appointmentID, allowsFailedRetry: false)
    }

    func resumePending() async {
        guard let snapshot = try? await careStore.snapshot() else { return }
        let pending = snapshot.sessionProcessing
            .filter { $0.stage != .ready && $0.failure == nil }
            .prefix(64)
        for record in pending {
            await startAndWait(appointmentID: record.appointmentID, allowsFailedRetry: false)
        }
    }

    func retry(appointmentID: UUID) async {
        await startAndWait(appointmentID: appointmentID, allowsFailedRetry: true)
    }

    func noteSummaryStarted(appointmentID: UUID) async throws {
        guard var record = await status(for: appointmentID), record.stage == .summarizing else {
            throw AIProviderError.invalidInput
        }
        record.summaryConsentGranted = true
        record.failure = nil
        try await persist(record)
        await startAndWait(appointmentID: appointmentID, allowsFailedRetry: true)
    }

    func noteSummaryCompleted(appointmentID: UUID, artifactID: UUID) async throws {
        let snapshot = try await careStore.snapshot()
        guard var appointment = snapshot.appointments.first(where: { $0.id == appointmentID }),
              let attachmentID = appointment.recordingAttachmentID,
              let artifact = snapshot.artifacts.first(where: { $0.id == artifactID && $0.kind == .sessionSummary }),
              artifact.sourceIDs.contains(appointmentID),
              artifact.sourceIDs.contains(attachmentID),
              snapshot.transcript.contains(where: { $0.appointmentID == appointmentID }),
              snapshot.transcript.filter({ $0.appointmentID == appointmentID }).allSatisfy({
                  artifact.sourceIDs.contains($0.id)
              }),
              decode(StructuredSessionSummaryResult.self, artifact: artifact) != nil else {
            throw AIProviderError.invalidInput
        }
        appointment.summaryID = artifactID
        appointment.status = .completed
        try await careStore.saveAppointment(appointment)
        let existing = snapshot.sessionProcessing.first { $0.appointmentID == appointmentID }
        var record = existing ?? newRecord(appointmentID: appointmentID)
        record.stage = .ready
        record.progress = 1
        record.failure = nil
        try await persist(record)
    }

    func events() async -> AsyncStream<SessionProcessingRecord> { eventStream }

    private func startAndWait(appointmentID: UUID, allowsFailedRetry: Bool) async {
        if let active = activeTasks[appointmentID] {
            await active.value
            return
        }
        let token = UUID()
        runTokens[appointmentID] = token
        let task = Task { [weak self] in
            guard let self else { return }
            await self.processIfEligible(
                appointmentID: appointmentID,
                token: token,
                allowsFailedRetry: allowsFailedRetry
            )
        }
        activeTasks[appointmentID] = task
        await task.value
        if runTokens[appointmentID] == token {
            activeTasks.removeValue(forKey: appointmentID)
            runTokens.removeValue(forKey: appointmentID)
        }
    }

    private func processIfEligible(
        appointmentID: UUID,
        token: UUID,
        allowsFailedRetry: Bool
    ) async {
        guard let snapshot = try? await careStore.snapshot() else { return }
        if let record = snapshot.sessionProcessing.first(where: { $0.appointmentID == appointmentID }) {
            if record.stage == .ready { return }
            if record.failure != nil, !allowsFailedRetry { return }
        }
        await process(appointmentID: appointmentID, token: token)
    }

    private func process(appointmentID: UUID, token: UUID) async {
        do {
            var context = try await loadContext(appointmentID: appointmentID)
            if context.record.failure != nil {
                context.record.failure = nil
                try await persist(context.record)
            }
            try Task.checkCancellation()
            context = try await transcribeIfNeeded(context, token: token)
            try Task.checkCancellation()
            context = try await diarizeIfNeeded(context, token: token)
            try Task.checkCancellation()
            try await summarizeIfAllowed(context, token: token)
        } catch is CancellationError {
            return
        } catch let failure as PipelineFailure {
            await persistFailure(failure, appointmentID: appointmentID)
        } catch {
            await persistFailure(await failureForCurrentStage(appointmentID), appointmentID: appointmentID)
        }
    }

    private func loadContext(appointmentID: UUID) async throws -> ProcessingContext {
        let snapshot = try await careStore.snapshot()
        guard snapshot.appointments.count <= Self.maximumItems,
              snapshot.attachments.count <= Self.maximumItems,
              snapshot.artifacts.count <= Self.maximumItems,
              var appointment = snapshot.appointments.first(where: { $0.id == appointmentID }) else {
            throw PipelineFailure.recordingMissing
        }
        var record = snapshot.sessionProcessing.first(where: { $0.appointmentID == appointmentID })
            ?? newRecord(appointmentID: appointmentID)
        try await persist(record)
        guard let attachmentID = appointment.recordingAttachmentID,
              let attachment = snapshot.attachments.first(where: {
                  $0.id == attachmentID && $0.kind == .audio && $0.byteCount > 0
              }) else {
            throw PipelineFailure.recordingMissing
        }
        let audioURL: URL
        do {
            audioURL = try await attachments.url(for: attachment)
            guard audioURL.isFileURL, FileManager.default.isReadableFile(atPath: audioURL.path) else {
                throw PipelineFailure.recordingMissing
            }
        } catch let failure as PipelineFailure {
            throw failure
        } catch {
            throw PipelineFailure.recordingMissing
        }
        let currentSources = [appointmentID, attachmentID]
        let discardExistingTranscript = appointment.transcriptID == nil
        let hasCurrentCheckpoint = snapshot.artifacts.contains {
            ($0.kind == .transcript || $0.kind == .diarization || $0.kind == .sessionSummary)
                && currentSources.allSatisfy($0.sourceIDs.contains)
        }
        if !hasCurrentCheckpoint {
            record.stage = .recordingSaved
            record.progress = 0
            record.summaryConsentGranted = false
            record.failure = nil
            appointment.transcriptID = nil
            appointment.summaryID = nil
        }
        appointment.status = .processing
        try await careStore.saveAppointment(appointment)
        try await persist(record)
        return ProcessingContext(
            snapshot: snapshot, appointment: appointment, attachment: attachment,
            audioURL: audioURL, record: record,
            discardExistingTranscript: discardExistingTranscript
        )
    }

    private func transcribeIfNeeded(_ input: ProcessingContext, token: UUID) async throws -> ProcessingContext {
        var context = input
        if let (artifact, result) = currentTranscriptCheckpoint(in: context) {
            context.transcriptResult = result
            if context.appointment.transcriptID != artifact.id {
                context.appointment.transcriptID = artifact.id
                try await careStore.saveAppointment(context.appointment)
            }
            return context
        }
        try await advance(&context.record, stage: .transcribing, progress: 0.1)
        let availability = await transcriber.availability(for: .current)
        guard availability == .available else { throw PipelineFailure.transcriptionUnavailable }
        let result: TranscriptResult
        do {
            result = try await transcriber.transcribeSession(audioURL: context.audioURL)
        } catch let failure as TranscriptionFailure where failure == .unavailableOnDevice || failure == .authorizationDenied {
            throw PipelineFailure.transcriptionUnavailable
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PipelineFailure.transcriptionFailed
        }
        guard Self.valid(result) else { throw PipelineFailure.transcriptionFailed }
        let artifact = try makeArtifact(
            kind: .transcript, sources: sourceIdentity(context), provider: transcriber.id,
            model: transcriber.id, payload: result
        )
        try await careStore.saveArtifact(artifact)
        context.appointment.transcriptID = artifact.id
        try await careStore.saveAppointment(context.appointment)
        context.snapshot.artifacts.append(artifact)
        context.transcriptResult = result
        guard runTokens[context.appointment.id] == token else { throw CancellationError() }
        return context
    }

    private func diarizeIfNeeded(_ input: ProcessingContext, token: UUID) async throws -> ProcessingContext {
        var context = input
        guard let transcriptResult = context.transcriptResult else { throw PipelineFailure.transcriptionFailed }
        if let (_, result) = currentDiarizationCheckpoint(in: context) {
            context.diarizationResult = result
        } else {
            try await advance(&context.record, stage: .separatingSpeakers, progress: 0.35)
            let result: DiarizationResult
            let appointmentID = context.appointment.id
            do {
                result = try await diarizer.diarize(audioURL: context.audioURL) { [weak self] progress in
                    Task { await self?.accept(progress, appointmentID: appointmentID, token: token) }
                }
            } catch let failure as DiarizationFailure where failure == .modelDownloadOffline {
                throw PipelineFailure.modelDownloadOffline
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw PipelineFailure.diarizationFailed
            }
            guard Self.valid(result) else { throw PipelineFailure.diarizationFailed }
            let artifact = try makeArtifact(
                kind: .diarization, sources: sourceIdentity(context), provider: diarizer.id,
                model: result.modelID, payload: result
            )
            try await careStore.saveArtifact(artifact)
            context.snapshot.artifacts.append(artifact)
            context.diarizationResult = result
        }
        guard let diarizationResult = context.diarizationResult else {
            throw PipelineFailure.diarizationFailed
        }
        do {
            try await careStore.saveSpeakerEmbeddings(
                diarizationResult.speakerEmbeddings,
                for: context.appointment.id
            )
        } catch {
            throw PipelineFailure.diarizationFailed
        }
        let existing = context.discardExistingTranscript ? [] : context.snapshot.transcript.filter {
            $0.appointmentID == context.appointment.id
        }
        if existing.isEmpty {
            guard let diarization = context.diarizationResult else { throw PipelineFailure.diarizationFailed }
            let segments: [TranscriptSegment]
            do {
                segments = try aligner.align(TranscriptAlignmentInput(
                    appointmentID: context.appointment.id, transcript: transcriptResult,
                    diarization: diarization, assignments: context.snapshot.speakerAssignments,
                    patientVoiceProfiles: context.snapshot.patientVoiceProfiles
                ))
            } catch {
                throw PipelineFailure.diarizationFailed
            }
            guard !segments.isEmpty else { throw PipelineFailure.diarizationFailed }
            try await careStore.replaceTranscriptSegments(segments, for: context.appointment.id)
            context.snapshot.transcript.removeAll { $0.appointmentID == context.appointment.id }
            context.snapshot.transcript.append(contentsOf: segments)
        }
        guard runTokens[context.appointment.id] == token else { throw CancellationError() }
        return context
    }

    private func summarizeIfAllowed(_ input: ProcessingContext, token: UUID) async throws {
        var context = input
        try await advance(&context.record, stage: .summarizing, progress: 0.75)
        if let artifact = currentSummaryArtifact(in: context) {
            try await noteSummaryCompleted(appointmentID: context.appointment.id, artifactID: artifact.id)
            return
        }
        guard context.record.summaryConsentGranted else {
            throw PipelineFailure.summaryPermissionRequired
        }
        let transcript = context.snapshot.transcript
            .filter { $0.appointmentID == context.appointment.id }
            .sorted { ($0.startMilliseconds, $0.id.uuidString) < ($1.startMilliseconds, $1.id.uuidString) }
        guard !transcript.isEmpty, transcript.count <= Self.maximumItems else { throw PipelineFailure.diarizationFailed }
        let summaryInput = StructuredSessionSummaryInput(
            appointmentID: context.appointment.id,
            template: context.appointment.kind == .tms ? .tms : .therapy,
            transcript: transcript.map {
                SessionTranscriptSource(
                    id: $0.id, speaker: $0.speaker, rawSpeakerLabel: $0.rawSpeakerLabel,
                    startMilliseconds: $0.startMilliseconds, endMilliseconds: $0.endMilliseconds, text: $0.text
                )
            },
            openTalkingPoints: context.snapshot.talkingPoints
                .filter { $0.status == .open && $0.targetAppointmentKind == context.appointment.kind }
                .prefix(64).map { SessionTalkingPointSource(id: $0.id, text: $0.text) }
        )
        let result: StructuredSessionSummaryResult
        do {
            result = try await summarizer.summarizeSession(summaryInput)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PipelineFailure.summaryFailed
        }
        guard result.template == summaryInput.template,
              runTokens[context.appointment.id] == token else { throw PipelineFailure.summaryFailed }
        let sources = sourceIdentity(context) + transcript.map(\.id)
        let artifact = try makeArtifact(
            kind: .sessionSummary, sources: sources, provider: result.metadata.provider,
            model: result.metadata.model, payload: result
        )
        do {
            try await careStore.saveArtifact(artifact)
            try await noteSummaryCompleted(appointmentID: context.appointment.id, artifactID: artifact.id)
        } catch {
            throw PipelineFailure.summaryFailed
        }
    }

    private func accept(_ progress: DiarizationProgress, appointmentID: UUID, token: UUID) async {
        guard runTokens[appointmentID] == token,
              var record = await status(for: appointmentID),
              record.stage == .separatingSpeakers, record.failure == nil else { return }
        let value: Double
        switch progress {
        case .checkingModels: value = 0.4
        case let .downloadingModels(fraction): value = 0.4 + 0.1 * min(max(fraction ?? 0, 0), 1)
        case let .processing(completed, total):
            guard total > 0 else { return }
            value = 0.5 + 0.2 * min(max(Double(completed) / Double(total), 0), 1)
        }
        let previous = record.progress ?? 0
        guard value >= previous else { return }
        record.progress = min(max(value, 0), 1)
        try? await persist(record)
    }

    private func persistFailure(_ failure: PipelineFailure, appointmentID: UUID) async {
        guard var record = await status(for: appointmentID) else { return }
        record.failure = failure.record
        try? await persist(record)
    }

    private func failureForCurrentStage(_ appointmentID: UUID) async -> PipelineFailure {
        guard let record = await status(for: appointmentID) else { return .recordingMissing }
        return switch record.stage {
        case .recordingSaved: .recordingMissing
        case .transcribing: .transcriptionFailed
        case .separatingSpeakers: .diarizationFailed
        case .summarizing, .ready: .summaryFailed
        }
    }

    private func advance(_ record: inout SessionProcessingRecord, stage: SessionProcessingStage, progress: Double) async throws {
        record.stage = stage
        record.progress = min(max(progress, 0), 1)
        record.failure = nil
        try await persist(record)
    }

    private func persist(_ record: SessionProcessingRecord) async throws {
        var updated = record
        updated.updatedAt = now()
        try await careStore.saveSessionProcessing(updated)
        eventContinuation.yield(updated)
    }

    private func newRecord(appointmentID: UUID) -> SessionProcessingRecord {
        SessionProcessingRecord(
            id: UUID(), appointmentID: appointmentID, stage: .recordingSaved, progress: 0,
            summaryConsentGranted: false, failure: nil, updatedAt: now()
        )
    }

    private func sourceIdentity(_ context: ProcessingContext) -> [UUID] {
        [context.appointment.id, context.attachment.id]
    }

    private func currentArtifacts(_ kind: AIArtifact.Kind, in context: ProcessingContext) -> [AIArtifact] {
        let sources = sourceIdentity(context)
        return context.snapshot.artifacts
            .filter { artifact in
                artifact.kind == kind && sources.allSatisfy(artifact.sourceIDs.contains)
            }
            .sorted {
                ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString)
            }
    }

    private func currentTranscriptCheckpoint(
        in context: ProcessingContext
    ) -> (AIArtifact, TranscriptResult)? {
        for artifact in currentArtifacts(.transcript, in: context).prefix(64) {
            guard let result = decode(TranscriptResult.self, artifact: artifact), Self.valid(result) else {
                continue
            }
            return (artifact, result)
        }
        return nil
    }

    private func currentDiarizationCheckpoint(
        in context: ProcessingContext
    ) -> (AIArtifact, DiarizationResult)? {
        for artifact in currentArtifacts(.diarization, in: context).prefix(64) {
            guard let result = decode(DiarizationResult.self, artifact: artifact), Self.valid(result) else {
                continue
            }
            return (artifact, result)
        }
        return nil
    }

    private func currentSummaryArtifact(in context: ProcessingContext) -> AIArtifact? {
        let transcriptIDs = Set(context.snapshot.transcript
            .filter { $0.appointmentID == context.appointment.id }.map(\.id))
        guard !transcriptIDs.isEmpty else { return nil }
        return context.snapshot.artifacts
            .filter { artifact in
                artifact.kind == .sessionSummary
                    && sourceIdentity(context).allSatisfy(artifact.sourceIDs.contains)
                    && transcriptIDs.allSatisfy(artifact.sourceIDs.contains)
            }
            .sorted {
                ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString)
            }
            .prefix(64)
            .first { decode(StructuredSessionSummaryResult.self, artifact: $0) != nil }
    }

    private func makeArtifact<Payload: Encodable>(
        kind: AIArtifact.Kind,
        sources: [UUID],
        provider: String,
        model: String,
        payload: Payload
    ) throws -> AIArtifact {
        let data = try PersistenceCoding.encode(payload)
        guard !data.isEmpty, !sources.isEmpty, !provider.isEmpty, !model.isEmpty else {
            throw AIProviderError.invalidResponse
        }
        return AIArtifact(
            id: UUID(), kind: kind, sourceIDs: sources, provider: provider, model: model,
            structuredPayload: data, createdAt: now()
        )
    }

    private func decode<Payload: Decodable>(_ type: Payload.Type, artifact: AIArtifact) -> Payload? {
        try? PersistenceCoding.decode(type, from: artifact.structuredPayload, table: "ai_artifacts", id: artifact.id.uuidString)
    }

    private static func valid(_ result: TranscriptResult) -> Bool {
        guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !result.segments.isEmpty, result.segments.count <= maximumItems else { return false }
        return result.segments.allSatisfy { piece in
            !piece.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && piece.startMilliseconds.map { $0 >= 0 } == true
                && piece.endMilliseconds.map { end in end > (piece.startMilliseconds ?? end) } == true
        }
    }

    private static func valid(_ result: DiarizationResult) -> Bool {
        guard !result.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !result.intervals.isEmpty, !result.speakerEmbeddings.isEmpty,
              result.intervals.count <= maximumItems, result.speakerEmbeddings.count <= 256 else { return false }
        return result.intervals.allSatisfy {
            !$0.rawSpeakerLabel.isEmpty && $0.startMilliseconds >= 0 && $0.endMilliseconds > $0.startMilliseconds
        } && result.speakerEmbeddings.allSatisfy {
            !$0.rawSpeakerLabel.isEmpty && !$0.modelID.isEmpty && !$0.values.isEmpty && $0.values.count <= 4_096
        }
    }
}

private struct ProcessingContext {
    var snapshot: CareSnapshot
    var appointment: Appointment
    let attachment: Attachment
    let audioURL: URL
    var record: SessionProcessingRecord
    var transcriptResult: TranscriptResult?
    var diarizationResult: DiarizationResult?
    let discardExistingTranscript: Bool
}

private enum PipelineFailure: Error {
    case recordingMissing
    case transcriptionUnavailable
    case transcriptionFailed
    case modelDownloadOffline
    case diarizationFailed
    case summaryPermissionRequired
    case summaryFailed

    var record: SessionProcessingFailure {
        switch self {
        case .recordingMissing:
            SessionProcessingFailure(code: .recordingMissing, message: "The recording is not available. Earlier saved material is unchanged.")
        case .transcriptionUnavailable:
            SessionProcessingFailure(code: .transcriptionUnavailable, message: "On-device transcription is not available. The recording is unchanged.")
        case .transcriptionFailed:
            SessionProcessingFailure(code: .transcriptionFailed, message: "Transcription could not finish. The recording is unchanged.")
        case .modelDownloadOffline:
            SessionProcessingFailure(code: .modelDownloadOffline, message: "Speaker separation needs its on-device model. Connect and retry. The recording and transcript are unchanged.")
        case .diarizationFailed:
            SessionProcessingFailure(code: .diarizationFailed, message: "Speaker separation could not finish. The recording and transcript are unchanged.")
        case .summaryPermissionRequired:
            SessionProcessingFailure(code: .summaryPermissionRequired, message: "Review what leaves this device before creating the debrief.")
        case .summaryFailed:
            SessionProcessingFailure(code: .summaryFailed, message: "The debrief could not be created. The recording and transcript are unchanged.")
        }
    }
}
