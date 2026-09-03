import FluidAudio
import Foundation

struct FluidAudioEngineSegment: Equatable, Sendable {
    let speakerID: String
    let startSeconds: Double
    let endSeconds: Double
    let confidence: Double?
}

struct FluidAudioEngineEmbeddingSample: Equatable, Sendable {
    let speakerID: String
    let values: [Float]
}

struct FluidAudioEngineResult: Equatable, Sendable {
    let segments: [FluidAudioEngineSegment]
    let embeddingSamples: [FluidAudioEngineEmbeddingSample]
}

protocol FluidAudioDiarizationEngine: Sendable {
    func prepareModels(progress: @escaping @Sendable (Double?) -> Void) async throws
    func process(
        audioURL: URL,
        progress: @escaping @Sendable (_ completed: Int, _ total: Int) -> Void
    ) async throws -> FluidAudioEngineResult
}

actor FluidAudioOfflineEngine: FluidAudioDiarizationEngine {
    // FluidAudio manages this read-mostly Core ML manager internally. The actor owns all calls.
    nonisolated(unsafe) private let manager: OfflineDiarizerManager

    init() {
        var configuration = OfflineDiarizerConfig()
        configuration.exposeChunkEmbeddings = true
        manager = OfflineDiarizerManager(config: configuration)
    }

    func prepareModels(progress: @escaping @Sendable (Double?) -> Void) async throws {
        try Task.checkCancellation()
        let models = try await OfflineDiarizerModels.load { snapshot in
            progress(snapshot.fractionCompleted)
        }
        try Task.checkCancellation()
        manager.initialize(models: models)
    }

    func process(
        audioURL: URL,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> FluidAudioEngineResult {
        try Task.checkCancellation()
        let result = try await manager.process(audioURL, progressCallback: progress)
        try Task.checkCancellation()
        return try Self.convert(
            segments: result.segments,
            speakerDatabase: result.speakerDatabase,
            chunkEmbeddings: result.chunkEmbeddings
        )
    }

    private static func convert(
        segments sourceSegments: [TimedSpeakerSegment],
        speakerDatabase: [String: [Float]]?,
        chunkEmbeddings: [ChunkEmbedding]?
    ) throws -> FluidAudioEngineResult {
        guard sourceSegments.count <= FluidAudioDiarizer.maximumIntervals else {
            throw DiarizationFailure.processingFailed
        }
        let segments = sourceSegments.map {
            FluidAudioEngineSegment(
                speakerID: $0.speakerId,
                startSeconds: Double($0.startTimeSeconds),
                endSeconds: Double($0.endTimeSeconds),
                confidence: Double($0.qualityScore)
            )
        }
        let samples = try embeddingSamples(
            segments: sourceSegments,
            speakerDatabase: speakerDatabase,
            chunkEmbeddings: chunkEmbeddings
        )
        return FluidAudioEngineResult(segments: segments, embeddingSamples: samples)
    }

    private static func embeddingSamples(
        segments: [TimedSpeakerSegment],
        speakerDatabase: [String: [Float]]?,
        chunkEmbeddings: [ChunkEmbedding]?
    ) throws -> [FluidAudioEngineEmbeddingSample] {
        if let chunks = chunkEmbeddings, !chunks.isEmpty {
            guard chunks.count <= FluidAudioDiarizer.maximumEmbeddingSamples else {
                throw DiarizationFailure.processingFailed
            }
            return chunks.map { FluidAudioEngineEmbeddingSample(speakerID: $0.speakerId, values: $0.embedding256) }
        }
        if let database = speakerDatabase, !database.isEmpty {
            guard database.count <= FluidAudioDiarizer.maximumEmbeddings else {
                throw DiarizationFailure.processingFailed
            }
            return database.keys.sorted().compactMap { speakerID in
                database[speakerID].map { FluidAudioEngineEmbeddingSample(speakerID: speakerID, values: $0) }
            }
        }
        guard segments.count <= FluidAudioDiarizer.maximumEmbeddingSamples else {
            throw DiarizationFailure.processingFailed
        }
        return segments.compactMap { segment in
            guard !segment.embedding.isEmpty else { return nil }
            return FluidAudioEngineEmbeddingSample(speakerID: segment.speakerId, values: segment.embedding)
        }
    }
}

actor FluidAudioDiarizer: CandyCornDiarizer {
    nonisolated let id: String

    static let modelID = "fluid-audio-offline-vbx-community-1"
    static let maximumIntervals = 100_000
    static let maximumEmbeddingSamples = 100_000
    static let maximumEmbeddings = 256
    static let maximumEmbeddingValues = 4_096

    private let engine: any FluidAudioDiarizationEngine
    private var modelsArePrepared = false
    private var preparation: (id: UUID, task: Task<Void, any Error>)?

    init() {
        id = Self.modelID
        engine = FluidAudioOfflineEngine()
    }

    init(engine: any FluidAudioDiarizationEngine, modelID: String = FluidAudioDiarizer.modelID) {
        let normalizedID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!normalizedID.isEmpty)
        id = normalizedID
        self.engine = engine
    }

    func diarize(
        audioURL: URL,
        progress: @escaping @Sendable (DiarizationProgress) -> Void
    ) async throws -> DiarizationResult {
        let emitter = DiarizationProgressEmitter(progress: progress)
        emitter.checkingModels()
        try Self.validateAudioURL(audioURL)
        try Task.checkCancellation()
        do {
            try await prepareModels { emitter.downloadingModels($0) }
        } catch {
            if Self.isCancellation(error) { throw CancellationError() }
            throw DiarizationFailure.modelPreparation(error)
        }
        try Task.checkCancellation()
        do {
            let rawResult = try await engine.process(audioURL: audioURL) { completed, total in
                emitter.processing(completed: completed, total: total)
            }
            try Task.checkCancellation()
            emitter.finishProcessing()
            return try Self.convert(rawResult, modelID: id)
        } catch {
            if Self.isCancellation(error) { throw CancellationError() }
            if let failure = error as? DiarizationFailure { throw failure }
            throw DiarizationFailure.processing(error)
        }
    }

    private func prepareModels(progress: @escaping @Sendable (Double?) -> Void) async throws {
        if modelsArePrepared { return }
        if let preparation {
            try await preparation.task.value
            modelsArePrepared = true
            return
        }
        let preparationID = UUID()
        let task = Task { try await engine.prepareModels(progress: progress) }
        preparation = (preparationID, task)
        do {
            try await task.value
            modelsArePrepared = true
            clearPreparation(id: preparationID)
        } catch {
            clearPreparation(id: preparationID)
            throw error
        }
    }

    private func clearPreparation(id: UUID) {
        guard preparation?.id == id else { return }
        preparation = nil
    }

    private static func validateAudioURL(_ url: URL) throws {
        guard url.isFileURL, !url.path.isEmpty else { throw DiarizationFailure.invalidAudio }
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw DiarizationFailure.invalidAudio }
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true, let size = values?.fileSize, size > 0 else {
            throw DiarizationFailure.invalidAudio
        }
    }

    private static func convert(_ raw: FluidAudioEngineResult, modelID: String) throws -> DiarizationResult {
        guard !raw.segments.isEmpty else { throw DiarizationFailure.emptyResult }
        guard raw.segments.count <= maximumIntervals else { throw DiarizationFailure.processingFailed }
        let intervals = try raw.segments.map(convertInterval)
            .sorted { lhs, rhs in
                if lhs.startMilliseconds != rhs.startMilliseconds { return lhs.startMilliseconds < rhs.startMilliseconds }
                if lhs.endMilliseconds != rhs.endMilliseconds { return lhs.endMilliseconds < rhs.endMilliseconds }
                return lhs.rawSpeakerLabel < rhs.rawSpeakerLabel
            }
        let embeddings = try aggregateEmbeddings(raw.embeddingSamples, modelID: modelID)
        guard !embeddings.isEmpty, embeddings.count <= maximumEmbeddings else {
            throw DiarizationFailure.processingFailed
        }
        let intervalLabels = Set(intervals.map(\.rawSpeakerLabel))
        let embeddingLabels = Set(embeddings.map(\.rawSpeakerLabel))
        guard intervalLabels == embeddingLabels else { throw DiarizationFailure.processingFailed }
        return DiarizationResult(intervals: intervals, speakerEmbeddings: embeddings, modelID: modelID)
    }

    private static func convertInterval(_ segment: FluidAudioEngineSegment) throws -> DiarizationInterval {
        guard segment.startSeconds.isFinite, segment.endSeconds.isFinite,
              segment.startSeconds >= 0, segment.endSeconds > segment.startSeconds else {
            throw DiarizationFailure.processingFailed
        }
        guard segment.confidence.map({ $0.isFinite && (0...1).contains($0) }) ?? true else {
            throw DiarizationFailure.processingFailed
        }
        let start = try milliseconds(segment.startSeconds)
        let end = try milliseconds(segment.endSeconds)
        guard end > start else { throw DiarizationFailure.processingFailed }
        return DiarizationInterval(
            rawSpeakerLabel: stableSpeakerLabel(segment.speakerID),
            startMilliseconds: start,
            endMilliseconds: end,
            confidence: segment.confidence
        )
    }

    private static func milliseconds(_ seconds: Double) throws -> Int {
        guard seconds.isFinite, seconds >= 0 else { throw DiarizationFailure.processingFailed }
        let scaled = seconds * 1_000
        guard scaled.isFinite, scaled <= Double(Int.max) else { throw DiarizationFailure.processingFailed }
        return Int(scaled.rounded(.toNearestOrAwayFromZero))
    }

    private static func aggregateEmbeddings(
        _ samples: [FluidAudioEngineEmbeddingSample],
        modelID: String
    ) throws -> [SpeakerEmbedding] {
        guard !samples.isEmpty, samples.count <= maximumEmbeddingSamples else {
            throw DiarizationFailure.processingFailed
        }
        var grouped: [String: [[Float]]] = [:]
        for sample in samples {
            let label = stableSpeakerLabel(sample.speakerID)
            guard (1...maximumEmbeddingValues).contains(sample.values.count), sample.values.allSatisfy(\.isFinite) else {
                throw DiarizationFailure.processingFailed
            }
            grouped[label, default: []].append(sample.values)
            guard grouped.count <= maximumEmbeddings else { throw DiarizationFailure.processingFailed }
        }
        return try grouped.keys.sorted().map { label in
            guard let values = grouped[label] else { throw DiarizationFailure.processingFailed }
            return SpeakerEmbedding(rawSpeakerLabel: label, modelID: modelID, values: try normalizedMean(values))
        }
    }

    private static func normalizedMean(_ vectors: [[Float]]) throws -> [Float] {
        guard let dimension = vectors.first?.count, (1...maximumEmbeddingValues).contains(dimension) else {
            throw DiarizationFailure.processingFailed
        }
        guard vectors.count <= maximumEmbeddingSamples,
              vectors.allSatisfy({ $0.count == dimension && $0.allSatisfy(\.isFinite) }) else {
            throw DiarizationFailure.processingFailed
        }
        var sums = [Double](repeating: 0, count: dimension)
        for vector in vectors {
            for index in 0..<dimension { sums[index] += Double(vector[index]) }
        }
        let magnitude = sqrt(sums.reduce(0) { $0 + ($1 * $1) })
        guard magnitude.isFinite, magnitude > 0 else { throw DiarizationFailure.processingFailed }
        let normalized = sums.map { Float($0 / magnitude) }
        guard normalized.allSatisfy(\.isFinite) else { throw DiarizationFailure.processingFailed }
        return normalized
    }

    private static func stableSpeakerLabel(_ raw: String) -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "speaker-unknown" : normalized
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        DiarizationFailure.isCancellation(error)
    }
}

private final class DiarizationProgressEmitter: @unchecked Sendable {
    private let lock = NSLock()
    private let progress: @Sendable (DiarizationProgress) -> Void
    private var greatestProcessingFraction = 0.0
    private var latestProcessingTotal: Int?

    init(progress: @escaping @Sendable (DiarizationProgress) -> Void) {
        self.progress = progress
    }

    func checkingModels() {
        progress(.checkingModels)
    }

    func downloadingModels(_ fraction: Double?) {
        let safeFraction = fraction.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil }
        progress(.downloadingModels(fractionCompleted: safeFraction))
    }

    func processing(completed: Int, total: Int) {
        guard total > 0 else { return }
        let safeCompleted = min(total, max(0, completed))
        let fraction = Double(safeCompleted) / Double(total)
        lock.lock()
        defer { lock.unlock() }
        guard fraction >= greatestProcessingFraction else { return }
        greatestProcessingFraction = fraction
        latestProcessingTotal = total
        progress(.processing(completed: safeCompleted, total: total))
    }

    func finishProcessing() {
        lock.lock()
        defer { lock.unlock() }
        guard greatestProcessingFraction < 1 else { return }
        let total = max(1, latestProcessingTotal ?? 1)
        greatestProcessingFraction = 1
        latestProcessingTotal = total
        progress(.processing(completed: total, total: total))
    }
}
