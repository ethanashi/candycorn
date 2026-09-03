import Foundation
import Testing
@testable import CandyCorn

@Suite("Resumable session processing")
struct SessionProcessingCoordinatorTests {
    @Test("Local checkpoints gate cloud summary and finish with durable pointers")
    func successfulPipeline() async throws {
        let fixture = try await makeFixture("success")
        defer { VaultTestSupport.remove(fixture.root) }
        let transcriber = FakeTranscriber()
        let diarizer = FakeDiarizer()
        let summarizer = FakeSessionSummarizer()
        let coordinator = makeCoordinator(fixture, transcriber, diarizer, summarizer)

        await coordinator.beginOrResume(appointmentID: fixture.appointment.id)
        var snapshot = try await fixture.store.snapshot()
        let waiting = try #require(snapshot.sessionProcessing.first)
        #expect(waiting.stage == .summarizing)
        #expect(waiting.failure?.code == .summaryPermissionRequired)
        #expect(snapshot.artifacts.filter { $0.kind == .transcript }.count == 1)
        #expect(snapshot.artifacts.filter { $0.kind == .diarization }.count == 1)
        #expect(snapshot.artifacts.filter { $0.kind == .sessionSummary }.isEmpty)
        #expect(await transcriber.sessionCallCount == 1)
        #expect(await diarizer.callCount == 1)

        try await coordinator.noteSummaryStarted(appointmentID: fixture.appointment.id)
        snapshot = try await fixture.store.snapshot()
        let completed = try #require(snapshot.appointments.first { $0.id == fixture.appointment.id })
        let ready = try #require(snapshot.sessionProcessing.first)
        #expect(ready.stage == .ready)
        #expect(ready.progress == 1)
        #expect(ready.summaryConsentGranted)
        #expect(completed.status == .completed)
        #expect(completed.transcriptID != nil)
        #expect(completed.summaryID != nil)
        #expect(snapshot.artifacts.filter { $0.kind == .sessionSummary }.count == 1)
        #expect(await summarizer.callCount == 1)
    }

    @Test("A new coordinator resumes from durable artifacts without repeating local work")
    func restartResume() async throws {
        let fixture = try await makeFixture("restart")
        defer { VaultTestSupport.remove(fixture.root) }
        let first = makeCoordinator(fixture, FakeTranscriber(), FakeDiarizer(), FakeSessionSummarizer())
        await first.beginOrResume(appointmentID: fixture.appointment.id)

        let transcriber = FakeTranscriber()
        let diarizer = FakeDiarizer()
        let summarizer = FakeSessionSummarizer()
        let resumed = makeCoordinator(fixture, transcriber, diarizer, summarizer)
        try await resumed.noteSummaryStarted(appointmentID: fixture.appointment.id)

        #expect(await transcriber.sessionCallCount == 0)
        #expect(await diarizer.callCount == 0)
        #expect(await summarizer.callCount == 1)
        #expect(await resumed.status(for: fixture.appointment.id)?.stage == .ready)
    }

    @Test("Launch recovery resumes an interrupted stage from its durable checkpoint")
    func resumePendingAfterRestart() async throws {
        let fixture = try await makeFixture("resume-pending")
        defer { VaultTestSupport.remove(fixture.root) }
        let firstTranscriber = FakeTranscriber()
        let firstDiarizer = SwitchableDiarizer()
        let first = makeCoordinator(
            fixture, firstTranscriber, firstDiarizer, FakeSessionSummarizer()
        )
        await first.beginOrResume(appointmentID: fixture.appointment.id)

        var snapshot = try await fixture.store.snapshot()
        #expect(snapshot.sessionProcessing.first?.failure?.code == .diarizationFailed)
        #expect(snapshot.artifacts.filter { $0.kind == .transcript }.count == 1)
        var interrupted = try #require(snapshot.sessionProcessing.first)
        interrupted.failure = nil
        try await fixture.store.saveSessionProcessing(interrupted)

        let resumedTranscriber = FakeTranscriber()
        let resumedDiarizer = FakeDiarizer()
        let resumed = makeCoordinator(
            fixture, resumedTranscriber, resumedDiarizer, FakeSessionSummarizer()
        )
        await resumed.resumePending()

        snapshot = try await fixture.store.snapshot()
        #expect(await resumedTranscriber.sessionCallCount == 0)
        #expect(await resumedDiarizer.callCount == 1)
        #expect(snapshot.artifacts.filter { $0.kind == .transcript }.count == 1)
        #expect(snapshot.artifacts.filter { $0.kind == .diarization }.count == 1)
        #expect(snapshot.sessionProcessing.first?.stage == .summarizing)
        #expect(snapshot.sessionProcessing.first?.failure?.code == .summaryPermissionRequired)
    }

    @Test("A transcription failure preserves the recording and retries only incomplete work")
    func transcriptionRetry() async throws {
        let fixture = try await makeFixture("transcription-retry")
        defer { VaultTestSupport.remove(fixture.root) }
        let transcriber = SwitchableTranscriber()
        let diarizer = FakeDiarizer()
        let coordinator = makeCoordinator(fixture, transcriber, diarizer, FakeSessionSummarizer())

        await coordinator.beginOrResume(appointmentID: fixture.appointment.id)
        var snapshot = try await fixture.store.snapshot()
        #expect(snapshot.sessionProcessing.first?.failure?.code == .transcriptionFailed)
        #expect(snapshot.attachments == [fixture.attachment])
        #expect(snapshot.artifacts.isEmpty)

        await transcriber.allowSuccess()
        await coordinator.retry(appointmentID: fixture.appointment.id)
        snapshot = try await fixture.store.snapshot()
        #expect(snapshot.sessionProcessing.first?.failure?.code == .summaryPermissionRequired)
        #expect(snapshot.artifacts.filter { $0.kind == .transcript }.count == 1)
        #expect(await transcriber.callCount == 2)
        #expect(await diarizer.callCount == 1)
    }

    @Test("Concurrent starts coalesce per appointment")
    func concurrentStart() async throws {
        let fixture = try await makeFixture("coalesce")
        defer { VaultTestSupport.remove(fixture.root) }
        let transcriber = FakeTranscriber()
        let diarizer = FakeDiarizer()
        let coordinator = makeCoordinator(fixture, transcriber, diarizer, FakeSessionSummarizer())

        async let first: Void = coordinator.beginOrResume(appointmentID: fixture.appointment.id)
        async let second: Void = coordinator.beginOrResume(appointmentID: fixture.appointment.id)
        _ = await (first, second)

        #expect(await transcriber.sessionCallCount == 1)
        #expect(await diarizer.callCount == 1)
    }

    @Test("A replacement recording never reuses artifacts from the previous source")
    func replacementRecordingRejectsOldArtifacts() async throws {
        let fixture = try await makeFixture("replacement-recording")
        defer { VaultTestSupport.remove(fixture.root) }
        let original = makeCoordinator(fixture, FakeTranscriber(), FakeDiarizer(), FakeSessionSummarizer())
        await original.beginOrResume(appointmentID: fixture.appointment.id)
        let before = try await fixture.store.snapshot()
        let oldTranscript = try #require(before.artifacts.first { $0.kind == .transcript })

        let replacement = CandyCorn.Attachment(
            id: UUID(), kind: .audio, relativePath: "audio/replacement.m4a",
            mediaType: "audio/mp4", byteCount: 2_048, durationMilliseconds: 9_000,
            createdAt: Date(timeIntervalSince1970: 1_900_000_100), isSample: false
        )
        try await fixture.store.saveAttachment(replacement)
        var appointment = fixture.appointment
        appointment.recordingAttachmentID = replacement.id
        appointment.transcriptID = nil
        appointment.summaryID = nil
        try await fixture.store.saveAppointment(appointment)

        let transcriber = FakeTranscriber()
        let diarizer = FakeDiarizer()
        let resumed = makeCoordinator(fixture, transcriber, diarizer, FakeSessionSummarizer())
        await resumed.beginOrResume(appointmentID: fixture.appointment.id)
        let after = try await fixture.store.snapshot()

        #expect(await transcriber.sessionCallCount == 1)
        #expect(await diarizer.callCount == 1)
        #expect(after.artifacts.filter { $0.kind == .transcript }.count == 2)
        #expect(after.artifacts.contains { artifact in
            artifact.kind == .transcript && artifact.sourceIDs.contains(replacement.id)
        })
        #expect(after.artifacts.contains { $0.id == oldTranscript.id && $0.structuredPayload == oldTranscript.structuredPayload })
    }

    @Test("Two appointments process independently")
    func multipleAppointmentsRemainIsolated() async throws {
        let fixture = try await makeFixture("multiple-appointments")
        defer { VaultTestSupport.remove(fixture.root) }
        let secondAttachment = CandyCorn.Attachment(
            id: UUID(), kind: .audio, relativePath: "audio/second.m4a",
            mediaType: "audio/mp4", byteCount: 1_024, durationMilliseconds: 9_000,
            createdAt: Date(timeIntervalSince1970: 1_900_000_200), isSample: false
        )
        let secondAppointment = Appointment(
            id: UUID(), kind: .therapy, scheduledAt: nil,
            startedAt: Date(timeIntervalSince1970: 1_900_000_190),
            endedAt: Date(timeIntervalSince1970: 1_900_000_199), providerID: nil,
            providerName: "Dr. Morgan", recordingAttachmentID: secondAttachment.id,
            transcriptID: nil, summaryID: nil, status: .processing
        )
        try await fixture.store.saveAttachment(secondAttachment)
        try await fixture.store.saveAppointment(secondAppointment)
        let transcriber = FakeTranscriber()
        let diarizer = FakeDiarizer()
        let coordinator = makeCoordinator(fixture, transcriber, diarizer, FakeSessionSummarizer())

        async let first: Void = coordinator.beginOrResume(appointmentID: fixture.appointment.id)
        async let second: Void = coordinator.beginOrResume(appointmentID: secondAppointment.id)
        _ = await (first, second)
        let snapshot = try await fixture.store.snapshot()

        #expect(await transcriber.sessionCallCount == 2)
        #expect(await diarizer.callCount == 2)
        #expect(snapshot.sessionProcessing.filter {
            $0.failure?.code == .summaryPermissionRequired
        }.count == 2)
        #expect(Set(snapshot.transcript.map(\.appointmentID)) == [fixture.appointment.id, secondAppointment.id])
    }

    @Test("Diarization retry reuses the byte-identical transcript checkpoint")
    func diarizationRetry() async throws {
        let fixture = try await makeFixture("diarization-retry")
        defer { VaultTestSupport.remove(fixture.root) }
        let transcriber = FakeTranscriber()
        let diarizer = SwitchableDiarizer()
        let coordinator = makeCoordinator(fixture, transcriber, diarizer, FakeSessionSummarizer())

        await coordinator.beginOrResume(appointmentID: fixture.appointment.id)
        let failed = try await fixture.store.snapshot()
        let transcript = try #require(failed.artifacts.first { $0.kind == .transcript })
        #expect(failed.sessionProcessing.first?.failure?.code == .diarizationFailed)

        await diarizer.allowSuccess()
        await coordinator.retry(appointmentID: fixture.appointment.id)
        let retried = try await fixture.store.snapshot()
        #expect(retried.artifacts.first { $0.kind == .transcript }?.structuredPayload == transcript.structuredPayload)
        #expect(retried.artifacts.filter { $0.kind == .transcript }.count == 1)
        #expect(await transcriber.sessionCallCount == 1)
        #expect(await diarizer.callCount == 2)
    }

    @Test("Summary retry keeps consent and sends the TMS text template only")
    func summaryRetryAndTMSTemplate() async throws {
        let fixture = try await makeFixture("summary-retry", kind: .tms)
        defer { VaultTestSupport.remove(fixture.root) }
        let transcriber = FakeTranscriber()
        let diarizer = FakeDiarizer()
        let summarizer = SwitchableSummarizer()
        let coordinator = makeCoordinator(fixture, transcriber, diarizer, summarizer)

        await coordinator.beginOrResume(appointmentID: fixture.appointment.id)
        try await coordinator.noteSummaryStarted(appointmentID: fixture.appointment.id)
        var snapshot = try await fixture.store.snapshot()
        #expect(snapshot.sessionProcessing.first?.failure?.code == .summaryFailed)
        #expect(snapshot.sessionProcessing.first?.summaryConsentGranted == true)
        #expect(await summarizer.lastInput?.template == .tms)

        await summarizer.allowSuccess()
        await coordinator.retry(appointmentID: fixture.appointment.id)
        snapshot = try await fixture.store.snapshot()
        #expect(snapshot.sessionProcessing.first?.stage == .ready)
        #expect(await transcriber.sessionCallCount == 1)
        #expect(await diarizer.callCount == 1)
        #expect(await summarizer.callCount == 2)
    }

    private func makeCoordinator(
        _ fixture: ProcessingFixture,
        _ transcriber: any CandyCornTranscriber,
        _ diarizer: any CandyCornDiarizer,
        _ summarizer: any CandyCornSessionSummarizer
    ) -> SessionProcessingCoordinator {
        SessionProcessingCoordinator(
            careStore: fixture.store,
            attachments: FixedAudioAttachmentStore(url: fixture.audioURL),
            transcriber: transcriber,
            diarizer: diarizer,
            aligner: TimestampTranscriptAligner(),
            summarizer: summarizer,
            now: { Date(timeIntervalSince1970: 1_900_000_000) }
        )
    }

    private func makeFixture(_ name: String, kind: Appointment.Kind = .therapy) async throws -> ProcessingFixture {
        let fixtureURL = try #require(Bundle(for: ProcessingFixtureBundleAnchor.self).url(
            forResource: "two-speaker-session", withExtension: "m4a"
        ))
        let (root, _, store, _, _) = try VaultTestSupport.make(name: "processing-\(name)-\(UUID().uuidString)")
        try await store.setSampleContentEnabled(false)
        let appointmentID = UUID()
        let attachment = CandyCorn.Attachment(
            id: UUID(), kind: .audio, relativePath: "audio/two-speaker-session.m4a",
            mediaType: "audio/mp4", byteCount: 1_024, durationMilliseconds: 9_000,
            createdAt: Date(timeIntervalSince1970: 1_899_999_000), isSample: false
        )
        let appointment = Appointment(
            id: appointmentID, kind: kind, scheduledAt: nil,
            startedAt: Date(timeIntervalSince1970: 1_899_999_000),
            endedAt: Date(timeIntervalSince1970: 1_899_999_009), providerID: nil,
            providerName: "Dr. Morgan", recordingAttachmentID: attachment.id,
            transcriptID: nil, summaryID: nil, status: .processing
        )
        try await store.saveAppointment(appointment)
        try await store.saveAttachment(attachment)
        return ProcessingFixture(
            root: root, store: store, appointment: appointment,
            attachment: attachment, audioURL: fixtureURL
        )
    }
}

private struct ProcessingFixture {
    let root: URL
    let store: VaultRepositories
    let appointment: Appointment
    let attachment: CandyCorn.Attachment
    let audioURL: URL
}

private final class ProcessingFixtureBundleAnchor {}

private struct FixedAudioAttachmentStore: AttachmentStore {
    let url: URL
    func allocateURL(kind: AttachmentKind, fileExtension: String) throws -> URL {
        _ = kind
        _ = fileExtension
        return url
    }
    func url(for attachment: CandyCorn.Attachment) throws -> URL {
        guard attachment.kind == .audio else { throw UserFacingError.playback }
        return url
    }
    func copyIntoExport(_ attachment: CandyCorn.Attachment, destination: URL) throws {
        _ = attachment
        _ = destination
    }
    func removeAll() {}
}

private actor SwitchableTranscriber: CandyCornTranscriber {
    nonisolated let id = "switchable-transcriber"
    private var shouldFail = true
    private(set) var callCount = 0

    func availability(for locale: Locale) -> LocalModelAvailability {
        _ = locale
        return .available
    }
    func transcribeJournal(audioURL: URL) throws -> TranscriptResult {
        try transcribeSession(audioURL: audioURL)
    }
    func transcribeSession(audioURL: URL) throws -> TranscriptResult {
        guard audioURL.isFileURL else { throw TranscriptionFailure.invalidAudio }
        callCount += 1
        if shouldFail { throw TranscriptionFailure.invalidAudio }
        return TranscriptResult(
            text: "I felt relief. Notice when guilt follows.",
            segments: [
                TranscriptPiece(text: "I felt relief.", startMilliseconds: 0, endMilliseconds: 1_000),
                TranscriptPiece(text: "Notice when guilt follows.", startMilliseconds: 1_100, endMilliseconds: 2_000),
            ]
        )
    }
    func allowSuccess() { shouldFail = false }
}

private actor SwitchableDiarizer: CandyCornDiarizer {
    nonisolated let id = "switchable-diarizer"
    private var shouldFail = true
    private(set) var callCount = 0

    func diarize(
        audioURL: URL,
        progress: @escaping @Sendable (DiarizationProgress) -> Void
    ) throws -> DiarizationResult {
        guard audioURL.isFileURL else { throw DiarizationFailure.invalidAudio }
        callCount += 1
        if shouldFail { throw DiarizationFailure.processingFailed }
        progress(.processing(completed: 1, total: 1))
        return DiarizationResult(
            intervals: [
                DiarizationInterval(rawSpeakerLabel: "speaker-a", startMilliseconds: 0, endMilliseconds: 4_000, confidence: 0.9),
                DiarizationInterval(rawSpeakerLabel: "speaker-b", startMilliseconds: 4_001, endMilliseconds: 9_000, confidence: 0.9),
            ],
            speakerEmbeddings: [
                SpeakerEmbedding(rawSpeakerLabel: "speaker-a", modelID: id, values: [0.1, 0.2]),
                SpeakerEmbedding(rawSpeakerLabel: "speaker-b", modelID: id, values: [0.2, 0.1]),
            ], modelID: id
        )
    }
    func allowSuccess() { shouldFail = false }
}

private actor SwitchableSummarizer: CandyCornSessionSummarizer {
    nonisolated let id = "switchable-summarizer"
    private var shouldFail = true
    private(set) var callCount = 0
    private(set) var lastInput: StructuredSessionSummaryInput?

    func summarizeSession(_ input: StructuredSessionSummaryInput) throws -> StructuredSessionSummaryResult {
        callCount += 1
        lastInput = input
        if shouldFail { throw AIProviderError.serviceUnavailable }
        return try FakeSummaryFactory.result(input)
    }
    func allowSuccess() { shouldFail = false }
}

private enum FakeSummaryFactory {
    static func result(_ input: StructuredSessionSummaryInput) throws -> StructuredSessionSummaryResult {
        guard let source = input.transcript.first else { throw AIProviderError.invalidInput }
        let citation = EvidenceCitation(
            sourceID: source.id, quote: source.text,
            timestampMilliseconds: source.startMilliseconds
        )
        let topics = (1...3).map { index in
            StructuredSessionSummaryItem(
                id: UUID(), text: "Debrief topic \(index)", provenance: .candyCorn,
                evidence: [citation], relatedEntityID: nil
            )
        }
        return StructuredSessionSummaryResult(
            template: input.template, debriefTopics: topics, sections: [],
            discussedTalkingPoints: [],
            metadata: AIResultMetadata(
                provider: "test-router", model: "test-model",
                usage: AIUsage(promptTokens: nil, completionTokens: nil, reasoningTokens: nil, totalTokens: nil, costCredits: nil)
            )
        )
    }
}
