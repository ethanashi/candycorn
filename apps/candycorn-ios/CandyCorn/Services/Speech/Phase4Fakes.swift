import Foundation

enum Phase4FakeError: Error, Equatable, Sendable {
    case configuredFailure
    case invalidConfiguration
    case invalidFileURL
}

actor FakeTranscriber: CandyCornTranscriber {
    nonisolated let id = "fake-transcriber"
    private let availabilityResult: LocalModelAvailability
    private let journalResult: TranscriptResult
    private let sessionResult: TranscriptResult
    private let failure: TranscriptionFailure?
    private(set) var availabilityCallCount = 0
    private(set) var journalCallCount = 0
    private(set) var sessionCallCount = 0

    init(
        availability: LocalModelAvailability = .available,
        journalResult: TranscriptResult? = nil,
        sessionResult: TranscriptResult? = nil,
        failure: TranscriptionFailure? = nil
    ) {
        availabilityResult = availability
        self.journalResult = journalResult ?? FakeTranscriber.screenshotTranscript
        self.sessionResult = sessionResult ?? FakeTranscriber.screenshotTranscript
        self.failure = failure
    }

    func availability(for locale: Locale) -> LocalModelAvailability {
        _ = locale.identifier
        availabilityCallCount += 1
        return availabilityResult
    }

    func transcribeJournal(audioURL: URL) throws -> TranscriptResult {
        try Self.validate(audioURL)
        journalCallCount += 1
        if let failure { throw failure }
        return journalResult
    }

    func transcribeSession(audioURL: URL) throws -> TranscriptResult {
        try Self.validate(audioURL)
        sessionCallCount += 1
        if let failure { throw failure }
        return sessionResult
    }

    private static func validate(_ url: URL) throws {
        guard url.isFileURL, !url.path.isEmpty else { throw Phase4FakeError.invalidFileURL }
    }

    private static let screenshotTranscript = TranscriptResult(
        text: "I want to understand why feeling better brings guilt. We can notice when that happens this week.",
        segments: [
            TranscriptPiece(text: "I want to understand why feeling better brings guilt.", startMilliseconds: 1_200, endMilliseconds: 4_800),
            TranscriptPiece(text: "We can notice when that happens this week.", startMilliseconds: 5_100, endMilliseconds: 8_400),
        ]
    )
}

actor FakeDiarizer: CandyCornDiarizer {
    nonisolated let id = "fake-diarizer"
    private let result: DiarizationResult
    private let failure: Phase4FakeError?
    private let progressEvents: [DiarizationProgress]
    private(set) var callCount = 0

    init(
        result: DiarizationResult? = nil,
        failure: Phase4FakeError? = nil,
        progress: [DiarizationProgress] = [.checkingModels, .downloadingModels(fractionCompleted: 1), .processing(completed: 2, total: 2)]
    ) {
        self.result = result ?? FakeDiarizer.screenshotResult
        self.failure = failure
        progressEvents = progress
    }

    func diarize(
        audioURL: URL,
        progress: @escaping @Sendable (DiarizationProgress) -> Void
    ) throws -> DiarizationResult {
        guard audioURL.isFileURL, !audioURL.path.isEmpty else { throw Phase4FakeError.invalidFileURL }
        guard progressEvents.count <= 100, progressEvents.allSatisfy(Self.valid) else {
            throw Phase4FakeError.invalidConfiguration
        }
        guard Self.valid(result) else { throw Phase4FakeError.invalidConfiguration }
        callCount += 1
        if let failure { throw failure }
        for event in progressEvents.prefix(100) { progress(event) }
        return result
    }

    private static func valid(_ progress: DiarizationProgress) -> Bool {
        switch progress {
        case .checkingModels:
            return true
        case let .downloadingModels(fraction):
            return fraction.map { $0.isFinite && (0...1).contains($0) } ?? true
        case let .processing(completed, total):
            return total > 0 && completed >= 0 && completed <= total
        }
    }

    private static func valid(_ result: DiarizationResult) -> Bool {
        let modelID = result.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelID.isEmpty, result.intervals.count <= 100_000,
              (1...256).contains(result.speakerEmbeddings.count) else { return false }
        let intervalsValid = result.intervals.allSatisfy {
            !$0.rawSpeakerLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.startMilliseconds >= 0 && $0.endMilliseconds > $0.startMilliseconds
                && ($0.confidence.map { $0.isFinite && (0...1).contains($0) } ?? true)
        }
        let embeddingsValid = result.speakerEmbeddings.allSatisfy {
            !$0.rawSpeakerLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && (1...4_096).contains($0.values.count) && $0.values.allSatisfy(\.isFinite)
        }
        return intervalsValid && embeddingsValid
    }

    private static let screenshotResult = DiarizationResult(
        intervals: [
            DiarizationInterval(rawSpeakerLabel: "speaker-0", startMilliseconds: 1_200, endMilliseconds: 4_800, confidence: 0.96),
            DiarizationInterval(rawSpeakerLabel: "speaker-1", startMilliseconds: 5_100, endMilliseconds: 8_400, confidence: 0.94),
        ],
        speakerEmbeddings: [
            SpeakerEmbedding(rawSpeakerLabel: "speaker-0", modelID: "fake-fluid-audio", values: [0.25, 0.5, 0.75]),
            SpeakerEmbedding(rawSpeakerLabel: "speaker-1", modelID: "fake-fluid-audio", values: [0.75, 0.5, 0.25]),
        ],
        modelID: "fake-fluid-audio"
    )
}

actor FakeSessionSummarizer: CandyCornSessionSummarizer {
    nonisolated let id = "fake-session-summarizer"
    private let configuredResult: StructuredSessionSummaryResult?
    private let failure: AIProviderError?
    private(set) var callCount = 0

    init(result: StructuredSessionSummaryResult? = nil, failure: AIProviderError? = nil) {
        configuredResult = result
        self.failure = failure
    }

    func summarizeSession(_ input: StructuredSessionSummaryInput) throws -> StructuredSessionSummaryResult {
        guard !input.transcript.isEmpty, input.transcript.count <= 100_000 else { throw AIProviderError.invalidInput }
        callCount += 1
        if let failure { throw failure }
        return configuredResult ?? Self.screenshotResult(for: input)
    }

    private static func screenshotResult(for input: StructuredSessionSummaryInput) -> StructuredSessionSummaryResult {
        let source = input.transcript[0]
        let citation = EvidenceCitation(
            sourceID: source.id,
            quote: source.text,
            timestampMilliseconds: source.startMilliseconds
        )
        let topics = [
            item("81000000-0000-0000-0000-000000000001", "Feeling better can bring up guilt.", .patient, citation),
            item("81000000-0000-0000-0000-000000000002", "You want to notice when that pattern appears.", .patient, citation),
            item("81000000-0000-0000-0000-000000000003", "Your provider suggested observing it this week.", .provider, citation),
        ]
        let kind: SessionSummarySectionKind = input.template == .therapy ? .homework : .providerInstructions
        let title = input.template == .therapy ? "Homework" : "Provider instructions"
        let section = StructuredSessionSummarySection(
            id: uuid("82000000-0000-0000-0000-000000000001"),
            kind: kind,
            title: title,
            items: [item("83000000-0000-0000-0000-000000000001", "Notice when guilt follows relief.", .provider, citation)]
        )
        return StructuredSessionSummaryResult(
            template: input.template,
            debriefTopics: topics,
            sections: [section],
            discussedTalkingPoints: [],
            metadata: AIResultMetadata(
                provider: "screenshot",
                model: "deterministic-session-summary",
                usage: AIUsage(promptTokens: nil, completionTokens: nil, reasoningTokens: nil, totalTokens: nil, costCredits: nil)
            )
        )
    }

    private static func item(
        _ id: String,
        _ text: String,
        _ provenance: SessionSummaryItemProvenance,
        _ citation: EvidenceCitation
    ) -> StructuredSessionSummaryItem {
        StructuredSessionSummaryItem(id: uuid(id), text: text, provenance: provenance, evidence: [citation], relatedEntityID: nil)
    }

    private static func uuid(_ value: String) -> UUID {
        guard let id = UUID(uuidString: value) else { preconditionFailure("Fixed fake UUID must be valid") }
        return id
    }
}

actor FakeSessionProcessing: SessionProcessing {
    private let records: [UUID: SessionProcessingRecord]
    private let eventRecords: [SessionProcessingRecord]
    private let failure: AIProviderError?
    private let configurationIsValid: Bool
    private(set) var statusCallCount = 0
    private(set) var beginCallCount = 0
    private(set) var resumeCallCount = 0
    private(set) var retryCallCount = 0
    private(set) var summaryStartCallCount = 0
    private(set) var summaryCompletionCallCount = 0

    init(
        records: [SessionProcessingRecord] = [],
        progress: [SessionProcessingRecord] = [],
        failure: AIProviderError? = nil
    ) {
        var indexed: [UUID: SessionProcessingRecord] = [:]
        var valid = records.count <= 100 && progress.count <= 100
        for record in records.prefix(100) {
            if indexed[record.appointmentID] != nil { valid = false }
            indexed[record.appointmentID] = record
            valid = valid && Self.valid(record)
        }
        self.records = indexed
        eventRecords = Array(progress.prefix(100))
        self.failure = failure
        configurationIsValid = valid && progress.allSatisfy(Self.valid)
    }

    func status(for appointmentID: UUID) -> SessionProcessingRecord? {
        statusCallCount += 1
        return configurationIsValid ? records[appointmentID] : nil
    }

    func beginOrResume(appointmentID: UUID) {
        _ = appointmentID
        beginCallCount += 1
    }

    func resumePending() {
        resumeCallCount += 1
    }

    func retry(appointmentID: UUID) {
        _ = appointmentID
        retryCallCount += 1
    }

    func noteSummaryStarted(appointmentID: UUID) throws {
        _ = appointmentID
        summaryStartCallCount += 1
        guard configurationIsValid else { throw Phase4FakeError.invalidConfiguration }
        if let failure { throw failure }
    }

    func noteSummaryCompleted(appointmentID: UUID, artifactID: UUID) throws {
        _ = appointmentID
        _ = artifactID
        summaryCompletionCallCount += 1
        guard configurationIsValid else { throw Phase4FakeError.invalidConfiguration }
        if let failure { throw failure }
    }

    func events() -> AsyncStream<SessionProcessingRecord> {
        let values = configurationIsValid ? eventRecords : []
        return AsyncStream { continuation in
            for value in values { continuation.yield(value) }
            continuation.finish()
        }
    }

    private static func valid(_ record: SessionProcessingRecord) -> Bool {
        let progressValid = record.progress.map { $0.isFinite && (0...1).contains($0) } ?? true
        let failureValid = record.failure.map {
            !$0.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? true
        return progressValid && failureValid
    }
}

struct UnavailableDiarizer: CandyCornDiarizer {
    let id = "unavailable-diarizer"

    func diarize(
        audioURL: URL,
        progress: @escaping @Sendable (DiarizationProgress) -> Void
    ) async throws -> DiarizationResult {
        guard audioURL.isFileURL else { throw Phase4FakeError.invalidFileURL }
        _ = progress
        throw AIProviderError.unavailable
    }
}

struct UnavailableSessionSummarizer: CandyCornSessionSummarizer {
    let id = "unavailable-session-summarizer"

    func summarizeSession(_ input: StructuredSessionSummaryInput) async throws -> StructuredSessionSummaryResult {
        guard !input.transcript.isEmpty else { throw AIProviderError.invalidInput }
        throw AIProviderError.unavailable
    }
}

struct UnavailableSessionProcessing: SessionProcessing {
    func status(for appointmentID: UUID) async -> SessionProcessingRecord? {
        _ = appointmentID
        return nil
    }

    func beginOrResume(appointmentID: UUID) async { _ = appointmentID }
    func resumePending() async {}
    func retry(appointmentID: UUID) async { _ = appointmentID }

    func noteSummaryStarted(appointmentID: UUID) async throws {
        _ = appointmentID
        throw AIProviderError.unavailable
    }

    func noteSummaryCompleted(appointmentID: UUID, artifactID: UUID) async throws {
        _ = appointmentID
        _ = artifactID
        throw AIProviderError.unavailable
    }

    func events() async -> AsyncStream<SessionProcessingRecord> {
        AsyncStream { $0.finish() }
    }
}
