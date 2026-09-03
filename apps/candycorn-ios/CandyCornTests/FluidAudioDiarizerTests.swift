import Foundation
import Testing
@testable import CandyCorn

@Suite("FluidAudio diarizer")
struct FluidAudioDiarizerTests {
    @Test("Concurrent calls share one model preparation and later calls reuse it")
    func preparationIsSharedAndReused() async throws {
        let audioURL = try Self.audioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let engine = TestFluidAudioEngine(prepareDelay: .milliseconds(50))
        let diarizer = FluidAudioDiarizer(engine: engine)

        async let first = diarizer.diarize(audioURL: audioURL) { _ in }
        async let second = diarizer.diarize(audioURL: audioURL) { _ in }
        let concurrentResults = try await [first, second]
        let third = try await diarizer.diarize(audioURL: audioURL) { _ in }

        #expect(concurrentResults.count == 2)
        #expect(third.intervals.count == 2)
        #expect(await engine.prepareCallCount == 1)
        #expect(await engine.processCallCount == 3)
    }

    @Test("Progress is ordered, clamped, monotonic, and completes")
    func progressIsTruthfulAndBounded() async throws {
        let audioURL = try Self.audioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let engine = TestFluidAudioEngine(
            modelProgress: [nil, -0.4, 0.4, 1.8, .nan],
            processingProgress: [(0, 4), (3, 4), (2, 4), (8, 4)]
        )
        let recorder = ProgressRecorder()
        let diarizer = FluidAudioDiarizer(engine: engine)

        _ = try await diarizer.diarize(audioURL: audioURL) { recorder.append($0) }

        #expect(recorder.snapshot() == [
            .checkingModels,
            .downloadingModels(fractionCompleted: nil),
            .downloadingModels(fractionCompleted: 0),
            .downloadingModels(fractionCompleted: 0.4),
            .downloadingModels(fractionCompleted: 1),
            .downloadingModels(fractionCompleted: nil),
            .processing(completed: 0, total: 4),
            .processing(completed: 3, total: 4),
            .processing(completed: 4, total: 4),
        ])
    }

    @Test("Intervals convert to milliseconds and embeddings use a normalized cluster mean")
    func resultConversionIsValidatedAndDeterministic() async throws {
        let audioURL = try Self.audioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let diarizer = FluidAudioDiarizer(engine: TestFluidAudioEngine())

        let result = try await diarizer.diarize(audioURL: audioURL) { _ in }

        #expect(result.modelID == FluidAudioDiarizer.modelID)
        #expect(result.intervals.map(\.rawSpeakerLabel) == ["speaker-a", "speaker-b"])
        #expect(result.intervals.map(\.startMilliseconds) == [100, 2_250])
        #expect(result.intervals.map(\.endMilliseconds) == [1_100, 3_000])
        #expect(result.intervals.map(\.confidence) == [0.8, 0.9])
        #expect(result.speakerEmbeddings.map(\.rawSpeakerLabel) == ["speaker-a", "speaker-b"])
        #expect(abs(result.speakerEmbeddings[0].values[0] - 0.707_106_77) < 0.000_01)
        #expect(abs(result.speakerEmbeddings[0].values[1] - 0.707_106_77) < 0.000_01)
        #expect(result.speakerEmbeddings[1].values == [0, 1])
    }

    @Test("Offline model preparation is classified and can be retried")
    func offlinePreparationCanBeRetried() async throws {
        let audioURL = try Self.audioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let engine = TestFluidAudioEngine(preparationFailuresRemaining: 1)
        let diarizer = FluidAudioDiarizer(engine: engine)

        await #expect(throws: DiarizationFailure.modelDownloadOffline) {
            _ = try await diarizer.diarize(audioURL: audioURL) { _ in }
        }
        let result = try await diarizer.diarize(audioURL: audioURL) { _ in }

        #expect(result.intervals.count == 2)
        #expect(await engine.prepareCallCount == 2)
    }

    @Test("An unrelated model failure is not mislabeled as offline")
    func installationFailureIsDistinctFromOffline() async throws {
        let audioURL = try Self.audioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let engine = TestFluidAudioEngine(preparationError: .installation)
        let diarizer = FluidAudioDiarizer(engine: engine)

        await #expect(throws: DiarizationFailure.modelInstallationFailed) {
            _ = try await diarizer.diarize(audioURL: audioURL) { _ in }
        }
    }

    @Test("Missing and empty files fail before model preparation")
    func invalidAudioDoesNotPrepareModels() async throws {
        let missingURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("m4a")
        let engine = TestFluidAudioEngine()
        let diarizer = FluidAudioDiarizer(engine: engine)

        await #expect(throws: DiarizationFailure.invalidAudio) {
            _ = try await diarizer.diarize(audioURL: missingURL) { _ in }
        }

        let emptyURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("m4a")
        try Data().write(to: emptyURL)
        defer { try? FileManager.default.removeItem(at: emptyURL) }
        await #expect(throws: DiarizationFailure.invalidAudio) {
            _ = try await diarizer.diarize(audioURL: emptyURL) { _ in }
        }
        #expect(await engine.prepareCallCount == 0)
    }

    @Test("Silence and malformed model output fail without partial results")
    func invalidResultsAreRejected() async throws {
        let audioURL = try Self.audioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let emptyDiarizer = FluidAudioDiarizer(
            engine: TestFluidAudioEngine(result: FluidAudioEngineResult(segments: [], embeddingSamples: []))
        )
        await #expect(throws: DiarizationFailure.emptyResult) {
            _ = try await emptyDiarizer.diarize(audioURL: audioURL) { _ in }
        }

        let invalid = FluidAudioEngineResult(
            segments: [
                FluidAudioEngineSegment(
                    speakerID: "speaker-a", startSeconds: 2, endSeconds: 1, confidence: 0.8
                ),
            ],
            embeddingSamples: [FluidAudioEngineEmbeddingSample(speakerID: "speaker-a", values: [.nan])]
        )
        let invalidDiarizer = FluidAudioDiarizer(engine: TestFluidAudioEngine(result: invalid))
        await #expect(throws: DiarizationFailure.processingFailed) {
            _ = try await invalidDiarizer.diarize(audioURL: audioURL) { _ in }
        }

        let missingEmbedding = FluidAudioEngineResult(
            segments: [
                FluidAudioEngineSegment(
                    speakerID: "speaker-a", startSeconds: 0, endSeconds: 1, confidence: nil
                ),
            ],
            embeddingSamples: []
        )
        let missingEmbeddingDiarizer = FluidAudioDiarizer(
            engine: TestFluidAudioEngine(result: missingEmbedding)
        )
        await #expect(throws: DiarizationFailure.processingFailed) {
            _ = try await missingEmbeddingDiarizer.diarize(audioURL: audioURL) { _ in }
        }
    }

    @Test("Cancellation remains cancellation during preparation and inference")
    func cancellationIsPreserved() async throws {
        let audioURL = try Self.audioFile()
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let preparing = FluidAudioDiarizer(engine: TestFluidAudioEngine(preparationError: .cancelled))
        await #expect(throws: CancellationError.self) {
            _ = try await preparing.diarize(audioURL: audioURL) { _ in }
        }

        let processing = FluidAudioDiarizer(engine: TestFluidAudioEngine(processingError: .cancelled))
        await #expect(throws: CancellationError.self) {
            _ = try await processing.diarize(audioURL: audioURL) { _ in }
        }
    }

    @Test("Live FluidAudio run is opt-in")
    func liveDiarizationIsDisabledByDefault() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CANDYCORN_RUN_LIVE_AUDIO_TESTS"] == "1",
              let path = environment["CANDYCORN_LIVE_AUDIO_URL"] else {
            return
        }
        let url = URL(fileURLWithPath: path)
        let result = try await FluidAudioDiarizer().diarize(audioURL: url) { _ in }
        #expect(!result.intervals.isEmpty)
        #expect((1...256).contains(result.speakerEmbeddings.count))
    }

    private static func audioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("m4a")
        try Data([0, 1, 2, 3]).write(to: url, options: .atomic)
        return url
    }
}

private enum TestEngineFailure: Error, Equatable, Sendable {
    case installation
    case cancelled
}

private actor TestFluidAudioEngine: FluidAudioDiarizationEngine {
    private(set) var prepareCallCount = 0
    private(set) var processCallCount = 0
    private var preparationFailuresRemaining: Int
    private let preparationError: TestEngineFailure?
    private let processingError: TestEngineFailure?
    private let prepareDelay: Duration
    private let modelProgress: [Double?]
    private let processingProgress: [(Int, Int)]
    private let result: FluidAudioEngineResult

    init(
        preparationFailuresRemaining: Int = 0,
        preparationError: TestEngineFailure? = nil,
        processingError: TestEngineFailure? = nil,
        prepareDelay: Duration = .zero,
        modelProgress: [Double?] = [],
        processingProgress: [(Int, Int)] = [(1, 2), (2, 2)],
        result: FluidAudioEngineResult = TestFluidAudioEngine.defaultResult
    ) {
        self.preparationFailuresRemaining = preparationFailuresRemaining
        self.preparationError = preparationError
        self.processingError = processingError
        self.prepareDelay = prepareDelay
        self.modelProgress = modelProgress
        self.processingProgress = processingProgress
        self.result = result
    }

    func prepareModels(progress: @escaping @Sendable (Double?) -> Void) async throws {
        prepareCallCount += 1
        if prepareDelay > .zero { try await Task.sleep(for: prepareDelay) }
        if preparationFailuresRemaining > 0 {
            preparationFailuresRemaining -= 1
            throw URLError(.notConnectedToInternet)
        }
        if let preparationError {
            if preparationError == .cancelled { throw CancellationError() }
            throw preparationError
        }
        for fraction in modelProgress.prefix(100) { progress(fraction) }
    }

    func process(
        audioURL: URL,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> FluidAudioEngineResult {
        guard audioURL.isFileURL, !audioURL.path.isEmpty else { throw DiarizationFailure.invalidAudio }
        processCallCount += 1
        if let processingError {
            if processingError == .cancelled { throw CancellationError() }
            throw processingError
        }
        for value in processingProgress.prefix(100) { progress(value.0, value.1) }
        return result
    }

    private static let defaultResult = FluidAudioEngineResult(
        segments: [
            FluidAudioEngineSegment(speakerID: "speaker-b", startSeconds: 2.25, endSeconds: 3, confidence: 0.9),
            FluidAudioEngineSegment(speakerID: "speaker-a", startSeconds: 0.1, endSeconds: 1.1, confidence: 0.8),
        ],
        embeddingSamples: [
            FluidAudioEngineEmbeddingSample(speakerID: "speaker-a", values: [1, 0]),
            FluidAudioEngineEmbeddingSample(speakerID: "speaker-a", values: [0, 1]),
            FluidAudioEngineEmbeddingSample(speakerID: "speaker-b", values: [0, 2]),
        ]
    )
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [DiarizationProgress] = []

    func append(_ event: DiarizationProgress) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func snapshot() -> [DiarizationProgress] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}
