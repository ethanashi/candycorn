import AVFAudio
import CoreMedia
import Foundation
import Speech

enum AppleSpeechAuthorization: Sendable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

enum AppleSpeechClientFailure: Error, Sendable {
    case unavailableOnDevice
    case invalidAudio
    case assetInstallationFailed
}

struct AppleSpeechRawSegment: Sendable {
    let text: String
    let timeRange: CMTimeRange
}

protocol AppleSpeechClient: Sendable {
    func availability(for locale: Locale) async -> LocalModelAvailability
    func authorizationStatus() async -> AppleSpeechAuthorization
    func requestAuthorization() async -> AppleSpeechAuthorization
    func installAssets(for locale: Locale) async throws
    func analyzeFile(at url: URL, locale: Locale) async throws -> [AppleSpeechRawSegment]
}

actor AppleSpeechTranscriber: CandyCornTranscriber {
    nonisolated let id = "apple-speech-transcriber"

    private static let maximumSegments = 100_000
    private let locale: Locale
    private let client: any AppleSpeechClient

    init(locale: Locale = .current, client: any AppleSpeechClient = SystemAppleSpeechClient()) {
        self.locale = locale
        self.client = client
    }

    func availability(for locale: Locale) async -> LocalModelAvailability {
        guard !locale.identifier.isEmpty else { return .unavailableOnDevice }
        return await client.availability(for: locale)
    }

    func transcribeJournal(audioURL: URL) async throws -> TranscriptResult {
        try await transcribe(audioURL: audioURL)
    }

    func transcribeSession(audioURL: URL) async throws -> TranscriptResult {
        try await transcribe(audioURL: audioURL)
    }

    private func transcribe(audioURL: URL) async throws -> TranscriptResult {
        guard Self.isReadableLocalFile(audioURL) else { throw TranscriptionFailure.invalidAudio }
        try Task.checkCancellation()
        try await authorize()

        let assetState = await client.availability(for: locale)
        guard assetState != .unavailableOnDevice else { throw TranscriptionFailure.unavailableOnDevice }
        if assetState == .downloadRequired {
            do {
                try await client.installAssets(for: locale)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw TranscriptionFailure.assetInstallationFailed
            }
        }

        do {
            let rawSegments = try await client.analyzeFile(at: audioURL, locale: locale)
            return try Self.makeResult(from: rawSegments)
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as TranscriptionFailure {
            throw failure
        } catch let failure as AppleSpeechClientFailure {
            throw Self.map(failure)
        } catch {
            throw TranscriptionFailure.invalidAudio
        }
    }

    private func authorize() async throws {
        let current = await client.authorizationStatus()
        let resolved = current == .notDetermined ? await client.requestAuthorization() : current
        guard resolved == .authorized else { throw TranscriptionFailure.authorizationDenied }
    }

    static func makeResult(from rawSegments: [AppleSpeechRawSegment]) throws -> TranscriptResult {
        guard !rawSegments.isEmpty, rawSegments.count <= maximumSegments else {
            throw TranscriptionFailure.emptyResult
        }

        var indexed: [(offset: Int, piece: TranscriptPiece)] = []
        indexed.reserveCapacity(rawSegments.count)
        for (offset, segment) in rawSegments.enumerated() {
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let start = try milliseconds(segment.timeRange.start)
            let end = try milliseconds(CMTimeRangeGetEnd(segment.timeRange))
            guard start >= 0, end > start else { throw TranscriptionFailure.invalidAudio }
            indexed.append((offset, TranscriptPiece(text: text, startMilliseconds: start, endMilliseconds: end)))
        }
        guard !indexed.isEmpty else { throw TranscriptionFailure.emptyResult }

        indexed.sort {
            let left = $0.piece.startMilliseconds ?? -1
            let right = $1.piece.startMilliseconds ?? -1
            return left == right ? $0.offset < $1.offset : left < right
        }
        var seen = Set<PieceIdentity>()
        let pieces = indexed.compactMap { item -> TranscriptPiece? in
            let identity = PieceIdentity(item.piece)
            return seen.insert(identity).inserted ? item.piece : nil
        }
        guard !pieces.isEmpty else { throw TranscriptionFailure.emptyResult }
        return TranscriptResult(text: pieces.map(\.text).joined(separator: " "), segments: pieces)
    }

    private static func milliseconds(_ time: CMTime) throws -> Int {
        guard time.isValid, time.isNumeric, time.timescale > 0 else {
            throw TranscriptionFailure.invalidAudio
        }
        let scaled = CMTimeConvertScale(time, timescale: 1_000, method: .roundHalfAwayFromZero)
        guard scaled.isValid, scaled.isNumeric, scaled.value >= 0,
              scaled.value <= Int64(Int.max) else { throw TranscriptionFailure.invalidAudio }
        return Int(scaled.value)
    }

    private static func isReadableLocalFile(_ url: URL) -> Bool {
        guard url.isFileURL, !url.path.isEmpty, url.path.hasPrefix("/") else { return false }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey]),
              values.isRegularFile == true, values.isReadable == true else { return false }
        return FileManager.default.isReadableFile(atPath: url.path)
    }

    private static func map(_ failure: AppleSpeechClientFailure) -> TranscriptionFailure {
        switch failure {
        case .unavailableOnDevice: .unavailableOnDevice
        case .invalidAudio: .invalidAudio
        case .assetInstallationFailed: .assetInstallationFailed
        }
    }
}

private struct PieceIdentity: Hashable {
    let text: String
    let start: Int?
    let end: Int?

    init(_ piece: TranscriptPiece) {
        text = piece.text
        start = piece.startMilliseconds
        end = piece.endMilliseconds
    }
}

actor SystemAppleSpeechClient: AppleSpeechClient {
    private static let maximumResults = 100_000

    func availability(for locale: Locale) async -> LocalModelAvailability {
        guard SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            return .unavailableOnDevice
        }
        let transcriber = Self.makeTranscriber(locale: supported)
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed: return .available
        case .supported, .downloading: return .downloadRequired
        case .unsupported: return .unavailableOnDevice
        @unknown default: return .unavailableOnDevice
        }
    }

    func authorizationStatus() -> AppleSpeechAuthorization {
        Self.mapAuthorization(SFSpeechRecognizer.authorizationStatus())
    }

    func requestAuthorization() async -> AppleSpeechAuthorization {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: Self.mapAuthorization(status))
            }
        }
    }

    func installAssets(for locale: Locale) async throws {
        guard SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw AppleSpeechClientFailure.unavailableOnDevice
        }
        let transcriber = Self.makeTranscriber(locale: supported)
        let initialStatus = await AssetInventory.status(forModules: [transcriber])
        guard initialStatus != .unsupported else { throw AppleSpeechClientFailure.unavailableOnDevice }
        guard initialStatus != .installed else { return }
        do {
            // A false return means this locale was already reserved, which is also success.
            try await AssetInventory.reserve(locale: supported)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
                throw AppleSpeechClientFailure.assetInstallationFailed
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as AppleSpeechClientFailure {
            throw failure
        } catch {
            throw AppleSpeechClientFailure.assetInstallationFailed
        }
    }

    func analyzeFile(at url: URL, locale: Locale) async throws -> [AppleSpeechRawSegment] {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw AppleSpeechClientFailure.unavailableOnDevice
        }
        let transcriber = Self.makeTranscriber(locale: supported)
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            throw AppleSpeechClientFailure.invalidAudio
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        async let collected = Self.collectResults(from: transcriber)
        do {
            _ = try await analyzer.analyzeSequence(from: audioFile)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            return try await collected
        } catch is CancellationError {
            await analyzer.cancelAndFinishNow()
            throw CancellationError()
        } catch {
            await analyzer.cancelAndFinishNow()
            throw AppleSpeechClientFailure.invalidAudio
        }
    }

    private static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange, .transcriptionConfidence]
        )
    }

    private static func collectResults(from transcriber: SpeechTranscriber) async throws -> [AppleSpeechRawSegment] {
        var segments: [AppleSpeechRawSegment] = []
        segments.reserveCapacity(256)
        var resultCount = 0
        for try await result in transcriber.results {
            try Task.checkCancellation()
            resultCount += 1
            guard resultCount <= maximumResults else { throw AppleSpeechClientFailure.invalidAudio }
            guard result.isFinal else { continue }
            let runSegments = segmentsFromRuns(result.text, fallback: result.range)
            segments.append(contentsOf: runSegments)
            guard segments.count <= maximumResults else { throw AppleSpeechClientFailure.invalidAudio }
        }
        return segments
    }

    private static func segmentsFromRuns(
        _ text: AttributedString,
        fallback: CMTimeRange
    ) -> [AppleSpeechRawSegment] {
        var segments: [AppleSpeechRawSegment] = []
        segments.reserveCapacity(min(text.runs.count, maximumResults))
        for run in text.runs.prefix(maximumResults) {
            let content = String(text[run.range].characters)
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            segments.append(AppleSpeechRawSegment(text: content, timeRange: run.audioTimeRange ?? fallback))
        }
        return segments
    }

    private static func mapAuthorization(_ status: SFSpeechRecognizerAuthorizationStatus) -> AppleSpeechAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        case .authorized: .authorized
        @unknown default: .restricted
        }
    }
}
