import Foundation
import Observation

enum RuntimeMode: Sendable, Equatable {
    case production
    case screenshot
}

struct RuntimeFactoryOutput: Sendable {
    let dependencies: AppDependencies
    let databaseURL: URL?
    let attachmentRootURL: URL?
}

struct RuntimeDependencyFactory: Sendable {
    typealias Builder = @Sendable () async throws -> RuntimeFactoryOutput

    let mode: RuntimeMode
    private let builder: Builder

    init(mode: RuntimeMode, builder: @escaping Builder) {
        self.mode = mode
        self.builder = builder
    }

    func make() async throws -> RuntimeFactoryOutput {
        try await builder()
    }

    static func selected(arguments: [String]) -> RuntimeDependencyFactory {
        if Route.parseLaunchArguments(arguments) != nil {
            return screenshot()
        }
        return production()
    }

    static func production() -> RuntimeDependencyFactory {
        RuntimeDependencyFactory(mode: .production) {
            let logger = PrivacyEventLogger()
            let attachments = try VaultAttachmentStore.applicationSupport()
            let keyStore = VaultKeyStore()
            let database = try VaultDatabase.applicationSupport(
                keyStore: keyStore,
                attachmentStore: attachments,
                logger: logger
            )
            return try await RuntimeDependencyFactory.productionOutput(
                database: database,
                attachments: attachments,
                logger: logger
            )
        }
    }

    static func production(
        databaseURL: URL,
        attachmentRootURL: URL,
        keyStore: any VaultKeyProviding,
        logger: any EventLogging = NoOpEventLogger()
    ) -> RuntimeDependencyFactory {
        RuntimeDependencyFactory(mode: .production) {
            guard databaseURL.isFileURL, attachmentRootURL.isFileURL else {
                throw RuntimeBootstrapError.unavailable
            }
            let attachments = try VaultAttachmentStore(rootURL: attachmentRootURL)
            let database = VaultDatabase(
                databaseURL: databaseURL,
                keyStore: keyStore,
                attachmentStore: attachments,
                logger: logger
            )
            return try await RuntimeDependencyFactory.productionOutput(
                database: database,
                attachments: attachments,
                logger: logger
            )
        }
    }

    static func screenshot() -> RuntimeDependencyFactory {
        RuntimeDependencyFactory(mode: .screenshot) {
            let store = InMemoryCareStore(snapshot: SeededData.careSnapshot)
            let attachments = InMemoryAttachmentStore()
            let dependencies = AppDependencies(
                careStore: store,
                maintenance: store,
                attachments: attachments,
                recording: ScreenshotRecordingService(attachments: attachments),
                playback: FakeAudioPlaybackService(),
                photos: FakePhotoAttachmentService(),
                exporter: FakeVaultExporter(store: store, attachments: attachments),
                logger: NoOpEventLogger(),
                screenshotMode: true,
                now: { Date(timeIntervalSince1970: 1_788_654_600) }
            )
            _ = try await dependencies.careStore.snapshot()
            return RuntimeFactoryOutput(
                dependencies: dependencies,
                databaseURL: nil,
                attachmentRootURL: nil
            )
        }
    }

    private static func productionOutput(
        database: VaultDatabase,
        attachments: VaultAttachmentStore,
        logger: any EventLogging
    ) async throws -> RuntimeFactoryOutput {
        try await database.open()
        let repositories = VaultRepositories(database: database, attachments: attachments, logger: logger)
        _ = try await repositories.snapshot()
        let registration = CareStoreAttachmentRegistrationSink(careStore: repositories)
        let recording = AVRecordingService(
            attachments: attachments,
            registration: registration,
            logger: logger,
            checkpoint: NoOpRecordingCheckpointSink()
        )
        let dependencies = AppDependencies(
            careStore: repositories,
            maintenance: database,
            attachments: attachments,
            recording: recording,
            playback: AVAudioPlaybackService(attachments: attachments),
            photos: LocalPhotoAttachmentService(
                attachments: attachments,
                registration: registration,
                logger: logger
            ),
            exporter: VaultExportService(
                store: repositories,
                maintenance: database,
                attachments: attachments,
                logger: logger
            ),
            logger: logger,
            screenshotMode: false,
            now: { Date() }
        )
        return RuntimeFactoryOutput(
            dependencies: dependencies,
            databaseURL: database.databaseURL,
            attachmentRootURL: attachments.rootURL
        )
    }
}

actor ScreenshotRecordingService: RecordingService {
    private let attachments: any AttachmentStore
    private let eventStream: AsyncStream<RecordingEvent>
    private let continuation: AsyncStream<RecordingEvent>.Continuation
    private var activeKind: RecordingKind?

    init(attachments: any AttachmentStore) {
        self.attachments = attachments
        let pair = AsyncStream.makeStream(
            of: RecordingEvent.self,
            bufferingPolicy: .bufferingNewest(4)
        )
        eventStream = pair.stream
        continuation = pair.continuation
    }

    func authorizationStatus() -> CaptureAuthorization { .authorized }

    func requestPermission() -> Bool { true }

    func start(kind: RecordingKind) throws {
        guard activeKind == nil else { throw UserFacingError.recording }
        activeKind = kind
        continuation.yield(.snapshot(Self.snapshot(for: kind)))
    }

    func stop(reason: RecordingStopReason) async throws -> LocalRecording {
        guard let activeKind else { throw UserFacingError.recording }
        self.activeKind = nil
        let duration = Self.snapshot(for: activeKind).elapsedMilliseconds
        let url = try await attachments.allocateURL(kind: .audio, fileExtension: "m4a")
        let attachment = Attachment(
            id: UUID(uuid: (0x2C, 0x6D, 0x41, 0x5E, 0xA1, 0x91, 0x4A, 0x16, 0x93, 0xC3, 0x11, 0x4C, 0xA0, 0xF8, 0x71, 0x20)),
            kind: .audio,
            relativePath: "audio/screenshot-recording.m4a",
            mediaType: "audio/mp4",
            byteCount: 1_024,
            durationMilliseconds: duration,
            createdAt: Date(timeIntervalSince1970: 1_788_654_600),
            isSample: false
        )
        let recording = LocalRecording(
            attachment: attachment,
            fileURL: url,
            stopReason: reason
        )
        continuation.yield(.stopped(recording))
        return recording
    }

    func events() -> AsyncStream<RecordingEvent> { eventStream }

    private static func snapshot(for kind: RecordingKind) -> RecordingSnapshot {
        let elapsed: Int
        switch kind {
        case .journal:
            elapsed = 42_000
        case .appointment:
            elapsed = AppointmentRecordingClock.initialSeconds * 1_000
        }
        return RecordingSnapshot(
            elapsedMilliseconds: elapsed,
            normalizedLevel: 0.64,
            isRecording: true
        )
    }
}

@MainActor
final class RuntimeGraph: Sendable {
    let mode: RuntimeMode
    let dependencies: AppDependencies
    let model: DemoState
    let databaseURL: URL?
    let attachmentRootURL: URL?

    init(mode: RuntimeMode, output: RuntimeFactoryOutput, arguments: [String]) {
        self.mode = mode
        dependencies = output.dependencies
        model = DemoState(dependencies: output.dependencies, arguments: arguments)
        databaseURL = output.databaseURL
        attachmentRootURL = output.attachmentRootURL
    }
}

enum RuntimeBootstrapError: Error, Equatable, Sendable {
    case unavailable
}

enum RuntimeBootstrapState {
    case idle
    case loading
    case failed(message: String)
    case ready(RuntimeGraph)
}

@MainActor @Observable
final class RuntimeBootstrap {
    private(set) var state: RuntimeBootstrapState = .idle
    private let arguments: [String]
    private let factory: RuntimeDependencyFactory
    @ObservationIgnored private var startTask: Task<RuntimeGraph, Error>?

    init(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        factory: RuntimeDependencyFactory? = nil
    ) {
        self.arguments = arguments
        self.factory = factory ?? RuntimeDependencyFactory.selected(arguments: arguments)
    }

    func start() async throws -> RuntimeGraph {
        if case let .ready(graph) = state {
            return graph
        }
        let task: Task<RuntimeGraph, Error>
        if let startTask {
            task = startTask
        } else {
            state = .loading
            let arguments = arguments
            let factory = factory
            task = Task {
                let output = try await Task.detached {
                    try await factory.make()
                }.value
                return RuntimeGraph(mode: factory.mode, output: output, arguments: arguments)
            }
            startTask = task
        }
        do {
            let graph = try await task.value
            startTask = nil
            state = .ready(graph)
            return graph
        } catch {
            startTask = nil
            state = .failed(message: UserFacingError.loading.message)
            throw RuntimeBootstrapError.unavailable
        }
    }
}
