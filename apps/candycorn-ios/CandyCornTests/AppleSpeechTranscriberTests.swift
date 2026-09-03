import CoreMedia
import Foundation
import Testing
@testable import CandyCorn

@Suite("Apple Speech file transcription")
struct AppleSpeechTranscriberTests {
    @Test("Availability maps installed, downloadable, and unsupported assets")
    func availabilityMapping() async {
        for (state, expected) in [
            (LocalModelAvailability.available, LocalModelAvailability.available),
            (.downloadRequired, .downloadRequired),
            (.unavailableOnDevice, .unavailableOnDevice),
        ] {
            let client = TestAppleSpeechClient(availability: state)
            let transcriber = AppleSpeechTranscriber(locale: Locale(identifier: "en_US"), client: client)
            #expect(await transcriber.availability(for: Locale(identifier: "en_US")) == expected)
            #expect(await client.authorizationRequests == 0)
            #expect(await client.analysisCalls == 0)
        }
    }

    @Test("Journal and session share timestamp conversion, sorting, and deduplication")
    func sharedAnalysisPath() async throws {
        let raw = [
            segment("second", start: 2.0004, duration: 0.4996),
            segment("first", start: 0.1005, duration: 0.8995),
            segment("second", start: 2.0004, duration: 0.4996),
        ]
        let client = TestAppleSpeechClient(segments: raw)
        let transcriber = AppleSpeechTranscriber(locale: Locale(identifier: "en_US"), client: client)
        let file = try makeReadableFile()
        defer { try? FileManager.default.removeItem(at: file) }

        let journal = try await transcriber.transcribeJournal(audioURL: file)
        let session = try await transcriber.transcribeSession(audioURL: file)

        #expect(journal == session)
        #expect(journal.text == "first second")
        #expect(journal.segments == [
            TranscriptPiece(text: "first", startMilliseconds: 101, endMilliseconds: 1_000),
            TranscriptPiece(text: "second", startMilliseconds: 2_000, endMilliseconds: 2_500),
        ])
        #expect(await client.analysisCalls == 2)
    }

    @Test("Download is installed before analysis and installation failure is narrow")
    func installationFailure() async throws {
        let client = TestAppleSpeechClient(
            availability: .downloadRequired,
            installError: AppleSpeechClientFailure.assetInstallationFailed
        )
        let transcriber = AppleSpeechTranscriber(client: client)
        let file = try makeReadableFile()
        defer { try? FileManager.default.removeItem(at: file) }

        await #expect(throws: TranscriptionFailure.assetInstallationFailed) {
            _ = try await transcriber.transcribeSession(audioURL: file)
        }
        #expect(await client.installCalls == 1)
        #expect(await client.analysisCalls == 0)
    }

    @Test("Denied and restricted authorization never start analysis")
    func authorizationDenied() async throws {
        for status in [AppleSpeechAuthorization.denied, .restricted] {
            let client = TestAppleSpeechClient(authorization: status)
            let transcriber = AppleSpeechTranscriber(client: client)
            let file = try makeReadableFile()
            defer { try? FileManager.default.removeItem(at: file) }
            await #expect(throws: TranscriptionFailure.authorizationDenied) {
                _ = try await transcriber.transcribeJournal(audioURL: file)
            }
            #expect(await client.analysisCalls == 0)
        }
    }

    @Test("Undetermined authorization is requested exactly once")
    func authorizationRequest() async throws {
        let client = TestAppleSpeechClient(authorization: .notDetermined, requestedAuthorization: .denied)
        let transcriber = AppleSpeechTranscriber(client: client)
        let file = try makeReadableFile()
        defer { try? FileManager.default.removeItem(at: file) }

        await #expect(throws: TranscriptionFailure.authorizationDenied) {
            _ = try await transcriber.transcribeJournal(audioURL: file)
        }
        #expect(await client.authorizationRequests == 1)
        #expect(await client.analysisCalls == 0)
    }

    @Test("Missing, negative, nonnumeric, and zero-length timing is rejected")
    func malformedTiming() async {
        let invalidRanges = [
            CMTimeRange(start: .invalid, duration: CMTime(seconds: 1, preferredTimescale: 1_000)),
            CMTimeRange(start: CMTime(seconds: -1, preferredTimescale: 1_000), duration: CMTime(seconds: 1, preferredTimescale: 1_000)),
            CMTimeRange(start: .zero, duration: .indefinite),
            CMTimeRange(start: .zero, duration: .zero),
        ]
        for range in invalidRanges {
            #expect(throws: TranscriptionFailure.invalidAudio) {
                _ = try AppleSpeechTranscriber.makeResult(from: [AppleSpeechRawSegment(text: "words", timeRange: range)])
            }
        }
    }

    @Test("Whitespace and absent recognition map to empty result")
    func emptyResults() {
        #expect(throws: TranscriptionFailure.emptyResult) {
            _ = try AppleSpeechTranscriber.makeResult(from: [])
        }
        #expect(throws: TranscriptionFailure.emptyResult) {
            _ = try AppleSpeechTranscriber.makeResult(from: [segment("  \n", start: 0, duration: 1)])
        }
    }

    @Test("Cancellation propagates unchanged")
    func cancellation() async throws {
        let client = TestAppleSpeechClient(analysisError: CancellationError())
        let transcriber = AppleSpeechTranscriber(client: client)
        let file = try makeReadableFile()
        defer { try? FileManager.default.removeItem(at: file) }
        await #expect(throws: CancellationError.self) {
            _ = try await transcriber.transcribeSession(audioURL: file)
        }
    }

    @Test("Only readable regular local files reach Speech")
    func fileValidation() async {
        let client = TestAppleSpeechClient()
        let transcriber = AppleSpeechTranscriber(client: client)
        let remote = URL(string: "https://example.invalid/recording.m4a")!
        let missing = URL(fileURLWithPath: "/tmp/candy-corn-missing-recording.m4a")

        await #expect(throws: TranscriptionFailure.invalidAudio) {
            _ = try await transcriber.transcribeJournal(audioURL: remote)
        }
        await #expect(throws: TranscriptionFailure.invalidAudio) {
            _ = try await transcriber.transcribeSession(audioURL: missing)
        }
        #expect(await client.analysisCalls == 0)
    }

    @Test("Live saved-file transcription", .disabled(if: !liveAudioEnabled))
    func liveSavedFile() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["CANDYCORN_LIVE_AUDIO_FILE"])
        let transcriber = AppleSpeechTranscriber(locale: Locale(identifier: "en_US"))
        let state = await transcriber.availability(for: Locale(identifier: "en_US"))
        guard state != .unavailableOnDevice else { return }
        let result = try await transcriber.transcribeSession(audioURL: URL(fileURLWithPath: path))
        #expect(!result.text.isEmpty)
        #expect(result.segments.allSatisfy { ($0.startMilliseconds ?? -1) >= 0 && ($0.endMilliseconds ?? -1) > ($0.startMilliseconds ?? -1) })
    }

    private static var liveAudioEnabled: Bool {
        ProcessInfo.processInfo.environment["CANDYCORN_RUN_LIVE_AUDIO_TESTS"] == "1"
    }

    private func segment(_ text: String, start: Double, duration: Double) -> AppleSpeechRawSegment {
        AppleSpeechRawSegment(
            text: text,
            timeRange: CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 1_000_000),
                duration: CMTime(seconds: duration, preferredTimescale: 1_000_000)
            )
        )
    }

    private func makeReadableFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "candy-corn-speech-\(UUID().uuidString).m4a")
        try Data([0, 1, 2, 3]).write(to: url, options: .withoutOverwriting)
        return url
    }
}

private actor TestAppleSpeechClient: AppleSpeechClient {
    private let availabilityResult: LocalModelAvailability
    private let authorization: AppleSpeechAuthorization
    private let requestedAuthorization: AppleSpeechAuthorization
    private let segments: [AppleSpeechRawSegment]
    private let installError: (any Error & Sendable)?
    private let analysisError: (any Error & Sendable)?
    private(set) var authorizationRequests = 0
    private(set) var installCalls = 0
    private(set) var analysisCalls = 0

    init(
        availability: LocalModelAvailability = .available,
        authorization: AppleSpeechAuthorization = .authorized,
        requestedAuthorization: AppleSpeechAuthorization = .authorized,
        segments: [AppleSpeechRawSegment] = [AppleSpeechRawSegment(
            text: "hello",
            timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1))
        )],
        installError: (any Error & Sendable)? = nil,
        analysisError: (any Error & Sendable)? = nil
    ) {
        availabilityResult = availability
        self.authorization = authorization
        self.requestedAuthorization = requestedAuthorization
        self.segments = segments
        self.installError = installError
        self.analysisError = analysisError
    }

    func availability(for locale: Locale) -> LocalModelAvailability {
        _ = locale.identifier
        return availabilityResult
    }

    func authorizationStatus() -> AppleSpeechAuthorization { authorization }

    func requestAuthorization() -> AppleSpeechAuthorization {
        authorizationRequests += 1
        return requestedAuthorization
    }

    func installAssets(for locale: Locale) throws {
        _ = locale.identifier
        installCalls += 1
        if let installError { throw installError }
    }

    func analyzeFile(at url: URL, locale: Locale) throws -> [AppleSpeechRawSegment] {
        _ = url.path
        _ = locale.identifier
        analysisCalls += 1
        if let analysisError { throw analysisError }
        return segments
    }
}
