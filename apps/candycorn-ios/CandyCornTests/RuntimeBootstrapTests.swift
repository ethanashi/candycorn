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
        let factory = RuntimeDependencyFactory.production(
            databaseURL: root.appending(path: "care.db"),
            attachmentRootURL: root.appending(path: "attachments", directoryHint: .isDirectory),
            keyStore: InMemoryVaultKeyStore(),
            logger: PrivacyEventLogger()
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
        #expect(graph.databaseURL == root.appending(path: "care.db").standardizedFileURL)
        #expect(graph.attachmentRootURL == root.appending(path: "attachments").standardizedFileURL)
        await (graph.dependencies.maintenance as? VaultDatabase)?.close()
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
        #expect(graph.dependencies.screenshotMode)
        #expect(graph.databaseURL == nil)
        #expect(graph.attachmentRootURL == nil)
        #expect(graph.model.consentAcknowledged)
        #expect(graph.model.appointmentRecording == .recording(startSeconds: 0))

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

private actor AttemptCounter {
    private(set) var value = 0

    func next() -> Int {
        value += 1
        return value
    }
}
