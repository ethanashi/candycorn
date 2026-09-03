import Foundation
import Testing
@testable import CandyCorn

@Suite("Runtime bootstrap")
@MainActor
struct RuntimeBootstrapTests {
    @Test("Normal launches select every production adapter")
    func productionSelection() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = BootCountingTransport()
        let factory = RuntimeDependencyFactory.production(
            databaseURL: root.appending(path: "care.db"),
            attachmentRootURL: root.appending(path: "attachments", directoryHint: .isDirectory),
            keyStore: InMemoryVaultKeyStore(),
            logger: PrivacyEventLogger(),
            openRouterKeyStore: InMemoryOpenRouterAPIKeyStore(),
            configurationStore: InMemoryAIConfigurationStore(),
            transport: transport
        )
        let bootstrap = RuntimeBootstrap(arguments: ["CandyCorn"], factory: factory)
        let graph = try await bootstrap.start()

        #expect(RuntimeDependencyFactory.selected(arguments: ["CandyCorn"]).mode == .production)
        #expect(graph.mode == .production)
        #expect(graph.dependencies.careStore is VaultRepositories)
        #expect(graph.dependencies.maintenance is VaultDatabase)
        #expect(graph.dependencies.attachments is VaultAttachmentStore)
        #expect(graph.dependencies.recording is AVRecordingService)
        #expect(graph.dependencies.playback is AVAudioPlaybackService)
        #expect(graph.dependencies.photos is LocalPhotoAttachmentService)
        #expect(graph.dependencies.exporter is VaultExportService)
        #expect(graph.dependencies.logger is PrivacyEventLogger)
        #expect(graph.dependencies.languageModel is OpenRouterLanguageModel)
        #expect(graph.dependencies.visionReader is OpenRouterVisionReader)
        #expect(graph.dependencies.transcriber is AppleSpeechTranscriber)
        #expect(graph.dependencies.diarizer is FluidAudioDiarizer)
        #expect(graph.dependencies.sessionSummarizer is OpenRouterSessionSummarizer)
        #expect(graph.dependencies.sessionProcessing is SessionProcessingCoordinator)
        #expect(graph.dependencies.distressClassifier is NoOpDistressSupportClassifier)
        #expect(await transport.callCount == 0)
        #expect(graph.databaseURL == root.appending(path: "care.db").standardizedFileURL)
        #expect(graph.attachmentRootURL == root.appending(path: "attachments").standardizedFileURL)
        await (graph.dependencies.maintenance as? VaultDatabase)?.close()
    }

    @Test("Recording checkpoints persist appointment timing and preserve care fields")
    func recordingCheckpointPersistence() async throws {
        let appointmentID = UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!
        let providerID = UUID(uuidString: "A1000000-0000-0000-0000-000000000002")!
        let attachmentID = UUID(uuidString: "A1000000-0000-0000-0000-000000000003")!
        let transcriptID = UUID(uuidString: "A1000000-0000-0000-0000-000000000004")!
        let summaryID = UUID(uuidString: "A1000000-0000-0000-0000-000000000005")!
        let scheduledAt = Date(timeIntervalSince1970: 1_900_000_000)
        let original = Appointment(
            id: appointmentID,
            kind: .psychiatry,
            scheduledAt: scheduledAt,
            startedAt: nil,
            endedAt: nil,
            providerID: providerID,
            providerName: "Dr. Morgan Lee",
            recordingAttachmentID: attachmentID,
            transcriptID: transcriptID,
            summaryID: summaryID,
            status: .planned,
            manualNotes: "Discuss the medication log."
        )
        var snapshot = SeededData.emptySnapshot
        snapshot.appointments = [original]
        let store = InMemoryCareStore(snapshot: snapshot)
        let clock = CheckpointWallClock(now: Date(timeIntervalSince1970: 2_000_000_000))
        let sink = CareStoreRecordingCheckpointSink(careStore: store, now: { clock.now() })

        try await sink.write(appointmentID: appointmentID, durationMilliseconds: 15_000)
        let firstSnapshot = await store.snapshot()
        var saved = try #require(firstSnapshot.appointments.first)
        let establishedStart = Date(timeIntervalSince1970: 1_999_999_985)
        #expect(saved.startedAt == establishedStart)
        #expect(saved.status == .recording)

        clock.advance(by: 15)
        try await sink.write(appointmentID: appointmentID, durationMilliseconds: 30_000)
        let secondSnapshot = await store.snapshot()
        saved = try #require(secondSnapshot.appointments.first)
        #expect(saved.startedAt == establishedStart)
        #expect(saved.kind == original.kind)
        #expect(saved.scheduledAt == original.scheduledAt)
        #expect(saved.endedAt == original.endedAt)
        #expect(saved.providerID == original.providerID)
        #expect(saved.providerName == original.providerName)
        #expect(saved.recordingAttachmentID == original.recordingAttachmentID)
        #expect(saved.transcriptID == original.transcriptID)
        #expect(saved.summaryID == original.summaryID)
        #expect(saved.manualNotes == original.manualNotes)

        await #expect(throws: UserFacingError.saving) {
            try await sink.write(appointmentID: UUID(), durationMilliseconds: 15_000)
        }
        await #expect(throws: UserFacingError.saving) {
            try await sink.write(appointmentID: appointmentID, durationMilliseconds: -1)
        }
    }

    @Test("Screenshot launches stay deterministic and off production paths")
    func screenshotSelection() async throws {
        let arguments = ["CandyCorn", "-screen", "/appointments/active"]
        let bootstrap = RuntimeBootstrap(arguments: arguments)
        let graph = try await bootstrap.start()

        #expect(RuntimeDependencyFactory.selected(arguments: arguments).mode == .screenshot)
        #expect(graph.mode == .screenshot)
        #expect(graph.dependencies.careStore is InMemoryCareStore)
        #expect(graph.dependencies.recording is ScreenshotRecordingService)
        #expect(graph.dependencies.playback is FakeAudioPlaybackService)
        #expect(graph.dependencies.photos is FakePhotoAttachmentService)
        #expect(graph.dependencies.exporter is FakeVaultExporter)
        #expect(graph.dependencies.languageModel is ScreenshotLanguageModel)
        #expect(graph.dependencies.visionReader is ScreenshotVisionReader)
        #expect(graph.dependencies.screenshotMode)
        #expect(graph.databaseURL == nil)
        #expect(graph.attachmentRootURL == nil)
        #expect(graph.model.consentAcknowledged)
        #expect(graph.model.appointmentRecording == .recording(startSeconds: 0))
        #expect(graph.model.hasOpenRouterKey)

        let appointment = try #require(SeededData.appointments.first)
        let events = await graph.dependencies.recording.events()
        try await graph.dependencies.recording.start(kind: .appointment(id: appointment.id))
        var iterator = events.makeAsyncIterator()
        #expect(await iterator.next() == .snapshot(RecordingSnapshot(
            elapsedMilliseconds: AppointmentRecordingClock.initialSeconds * 1_000,
            normalizedLevel: 0.64,
            isRecording: true
        )))
    }

    @Test("Sheet scenarios are parsed only in screenshot mode")
    func screenshotScenarioSelection() async throws {
        let arguments = ["CandyCorn", "-screen", "/settings/ai", "-sheet", "openrouter-key"]
        let graph = try await RuntimeBootstrap(arguments: arguments).start()

        #expect(graph.dependencies.screenshotScenario == .openRouterKey)
        #expect(ScreenshotScenario.parse(arguments: arguments) == .openRouterKey)
        #expect(ScreenshotScenario.parse(arguments: ["CandyCorn", "-sheet", "unknown"]) == nil)
    }

    @Test("A failed start can retry and duplicate starts share one graph")
    func retryAndDeduplication() async throws {
        let attempts = AttemptCounter()
        let factory = RuntimeDependencyFactory(mode: .screenshot) {
            let attempt = await attempts.next()
            if attempt == 1 { throw RuntimeBootstrapError.unavailable }
            return RuntimeFactoryOutput(
                dependencies: PreviewDependencies.make(screenshotMode: true),
                databaseURL: nil,
                attachmentRootURL: nil
            )
        }
        let bootstrap = RuntimeBootstrap(
            arguments: ["CandyCorn", "-screen", "/today"],
            factory: factory
        )

        await #expect(throws: RuntimeBootstrapError.unavailable) {
            _ = try await bootstrap.start()
        }
        guard case let .failed(message) = bootstrap.state else {
            Issue.record("A failed factory must produce the recoverable failure state")
            return
        }
        #expect(message == UserFacingError.loading.message)

        async let first = bootstrap.start()
        async let second = bootstrap.start()
        let (firstGraph, secondGraph) = try await (first, second)
        let repeatedGraph = try await bootstrap.start()

        #expect(firstGraph === secondGraph)
        #expect(firstGraph === repeatedGraph)
        #expect(await attempts.value == 2)
        guard case .ready = bootstrap.state else {
            Issue.record("A successful retry must produce the ready state")
            return
        }
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "candycorn-runtime-bootstrap-tests")
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }
}

private actor BootCountingTransport: AIHTTPTransport {
    private(set) var callCount = 0

    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        callCount += 1
        throw AIProviderError.serviceUnavailable
    }
}

private actor AttemptCounter {
    private(set) var value = 0

    func next() -> Int {
        value += 1
        return value
    }
}

private final class CheckpointWallClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(now: Date) {
        current = now
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(seconds)
    }
}
