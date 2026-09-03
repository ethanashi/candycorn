import Foundation

struct AIModelConfiguration: Codable, Equatable, Sendable {
    static let defaults = AIModelConfiguration(
        organizerModelID: "deepseek/deepseek-v4-flash-0731",
        visionModelID: "deepseek/deepseek-v4-flash-vision-exp"
    )

    var organizerModelID: String
    var visionModelID: String
}

struct AIUsage: Codable, Equatable, Sendable {
    var promptTokens: Int?
    var completionTokens: Int?
    var reasoningTokens: Int?
    var totalTokens: Int?
    var costCredits: Double?
}

struct AIResultMetadata: Codable, Equatable, Sendable {
    let provider: String
    let model: String
    let usage: AIUsage
}

struct SourceTextDocument: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case journal, extractedPhotoText, sessionNotes, homework, goal, talkingPoint, moodTrend
    }

    let id: UUID
    let kind: Kind
    let title: String
    let text: String
    let occurredAt: Date?
}

struct EvidenceCitation: Codable, Equatable, Sendable {
    let sourceID: UUID
    let quote: String
    let timestampMilliseconds: Int?
}

struct EvidenceBackedStatement: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let text: String
    let evidence: [EvidenceCitation]
}

struct RewriteSegment: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let text: String
    let evidence: [EvidenceCitation]
}

struct RewriteJournalInput: Codable, Equatable, Sendable {
    let source: SourceTextDocument
    let preserveExplicitLanguage: Bool
}

struct RewriteJournalResult: Codable, Equatable, Sendable {
    let segments: [RewriteSegment]
    let unclearAreas: [String]
    let metadata: AIResultMetadata
}

struct JournalSummaryInput: Codable, Equatable, Sendable { let source: SourceTextDocument }

struct JournalSummaryResult: Codable, Equatable, Sendable {
    let statements: [EvidenceBackedStatement]
    let metadata: AIResultMetadata
}

struct JournalSignals: Codable, Equatable, Sendable {
    struct EvidenceItem: Codable, Equatable, Sendable {
        let label: String
        let evidence: String
    }

    struct Commitment: Codable, Equatable, Sendable, Identifiable {
        let id: UUID
        let text: String
        let cadenceHint: String?
        let evidence: String
    }

    struct TalkingPointSuggestion: Codable, Equatable, Sendable, Identifiable {
        let id: UUID
        let text: String
        let reason: String
        let evidence: String
    }

    let summary: String
    let emotions: [EvidenceItem]
    let explicitCommitments: [Commitment]
    let talkingPointSuggestions: [TalkingPointSuggestion]
    let possibleThemes: [EvidenceItem]
}

struct JournalSignalInput: Codable, Equatable, Sendable { let source: SourceTextDocument }

struct JournalSignalResult: Codable, Equatable, Sendable {
    let signals: JournalSignals
    let metadata: AIResultMetadata
}

struct SessionSummarySection: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let title: String
    let statements: [EvidenceBackedStatement]
}

struct SessionSummaryInput: Codable, Equatable, Sendable {
    let appointmentID: UUID
    let appointmentKind: Appointment.Kind
    let manualNotes: SourceTextDocument
}

struct SessionSummaryResult: Codable, Equatable, Sendable {
    let sections: [SessionSummarySection]
    let metadata: AIResultMetadata
}

struct AppointmentBriefSection: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let title: String
    var statements: [EvidenceBackedStatement]
}

struct AppointmentBriefInput: Equatable, Sendable {
    let appointmentKind: Appointment.Kind
    let contextPacket: ContextPacket

    var sources: [SourceTextDocument] { contextPacket.sources }

    init(appointmentKind: Appointment.Kind, contextPacket: ContextPacket) {
        self.appointmentKind = appointmentKind
        self.contextPacket = contextPacket
    }

    // nyx: This compatibility initializer keeps Phase 3 fixtures source-compatible. Runtime preparation always supplies a retrieved packet.
    init(appointmentKind: Appointment.Kind, sources: [SourceTextDocument]) {
        let now = sources.compactMap(\.occurredAt).max() ?? Date(timeIntervalSince1970: 0)
        let request = MemoryRetrievalRequest(
            appointmentKind: appointmentKind,
            window: DateInterval(start: now, end: now),
            now: now
        )
        let items = sources.map { source in
            ContextPacketItem(
                id: source.id,
                sourceIDs: [source.id],
                kind: Self.packetKind(source.kind),
                title: source.title,
                text: source.text,
                occurredAt: source.occurredAt,
                provenance: .user,
                evidence: [],
                relevanceRank: nil
            )
        }
        contextPacket = ContextPacket(
            request: request,
            items: items,
            text: sources.map(\.text).joined(separator: "\n\n"),
            omittedItemCount: 0
        )
        self.appointmentKind = appointmentKind
    }

    private static func packetKind(_ kind: SourceTextDocument.Kind) -> ContextPacketItem.Kind {
        switch kind {
        case .sessionNotes: .sessionSummary
        case .homework: .homework
        case .goal: .activeGoal
        case .talkingPoint: .talkingPoint
        case .journal, .extractedPhotoText: .journal
        case .moodTrend: .moodTrend
        }
    }
}

struct AppointmentBriefResult: Codable, Equatable, Sendable {
    var sections: [AppointmentBriefSection]
    var userEditedAt: Date?
    let metadata: AIResultMetadata
}

struct TranscriptPiece: Codable, Equatable, Sendable {
    let text: String
    let startMilliseconds: Int?
    let endMilliseconds: Int?
}

struct TranscriptResult: Codable, Equatable, Sendable {
    let text: String
    let segments: [TranscriptPiece]
}

enum LocalModelAvailability: Equatable, Sendable {
    case available
    case downloadRequired
    case unavailableOnDevice
}

enum TranscriptionFailure: Error, Equatable, Sendable {
    case unavailableOnDevice
    case assetInstallationFailed
    case authorizationDenied
    case invalidAudio
    case emptyResult
}

struct DiarizationInterval: Codable, Equatable, Sendable {
    let rawSpeakerLabel: String
    let startMilliseconds: Int
    let endMilliseconds: Int
    let confidence: Double?
}

struct SpeakerEmbedding: Codable, Equatable, Sendable {
    let rawSpeakerLabel: String
    let modelID: String
    let values: [Float]
}

enum DiarizationProgress: Equatable, Sendable {
    case checkingModels
    case downloadingModels(fractionCompleted: Double?)
    case processing(completed: Int, total: Int)
}

struct DiarizationResult: Codable, Equatable, Sendable {
    let intervals: [DiarizationInterval]
    let speakerEmbeddings: [SpeakerEmbedding]
    let modelID: String
}

struct SessionTranscriptSource: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let speaker: TranscriptSegment.Speaker
    let rawSpeakerLabel: String?
    let startMilliseconds: Int
    let endMilliseconds: Int
    let text: String
}

struct SessionTalkingPointSource: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let text: String
}

enum SessionSummaryTemplate: String, Codable, Sendable {
    case therapy
    case tms
}

enum SessionSummarySectionKind: String, Codable, CaseIterable, Sendable {
    case mainTopics
    case patientRealizations
    case providerObservations
    case homework
    case goals
    case beliefsOrStuckPoints
    case copingTools
    case questionsToRevisit
    case unfinishedTopics
    case nextSessionItems
    case currentFeelingsBeforeSession
    case distressOrAnxiety
    case triggersOrProvocations
    case questionsForProvider
    case providerInstructions
    case changesDiscussed
    case feelingsAfterSession
    case thingsToMonitor
}

enum SessionSummaryItemProvenance: String, Codable, Sendable {
    case patient
    case provider
    case candyCorn
}

struct StructuredSessionSummaryItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let text: String
    let provenance: SessionSummaryItemProvenance
    let evidence: [EvidenceCitation]
    let relatedEntityID: UUID?
}

struct StructuredSessionSummarySection: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let kind: SessionSummarySectionKind
    let title: String
    let items: [StructuredSessionSummaryItem]
}

struct StructuredSessionSummaryInput: Codable, Equatable, Sendable {
    let appointmentID: UUID
    let template: SessionSummaryTemplate
    let transcript: [SessionTranscriptSource]
    let openTalkingPoints: [SessionTalkingPointSource]
}

struct StructuredSessionSummaryResult: Codable, Equatable, Sendable {
    let template: SessionSummaryTemplate
    let debriefTopics: [StructuredSessionSummaryItem]
    let sections: [StructuredSessionSummarySection]
    let discussedTalkingPoints: [StructuredSessionSummaryItem]
    let metadata: AIResultMetadata
}

struct VisionReadInput: Sendable {
    let journalID: UUID
    let attachmentID: UUID
    let mediaType: String
    let imageData: Data
}

struct VisionReadResult: Codable, Equatable, Sendable {
    let text: String
    let uncertainSpans: [String]
    let metadata: AIResultMetadata
}

struct DistressClassificationInput: Equatable, Sendable {
    let sourceID: UUID
    let text: String
}

struct DistressAssessment: Codable, Equatable, Sendable {
    enum Level: String, Codable, Sendable { case normal, elevatedSupport, urgentSupport, immediateDangerSignal }
    enum SuggestedUI: String, Codable, Sendable { case none, gentleSupport, humanSupport, urgentHumanSupport }

    let level: Level
    let evidenceSpans: [String]
    let uncertainty: Double
    let suggestedUI: SuggestedUI
}

protocol CandyCornLanguageModel: Sendable {
    var id: String { get }
    func rewriteJournal(_ input: RewriteJournalInput) async throws -> RewriteJournalResult
    func summarizeJournal(_ input: JournalSummaryInput) async throws -> JournalSummaryResult
    func extractJournalSignals(_ input: JournalSignalInput) async throws -> JournalSignalResult
    func summarizeSession(_ input: SessionSummaryInput) async throws -> SessionSummaryResult
    func generateAppointmentBrief(_ input: AppointmentBriefInput) async throws -> AppointmentBriefResult
}

protocol CandyCornTranscriber: Sendable {
    var id: String { get }
    func availability(for locale: Locale) async -> LocalModelAvailability
    func transcribeJournal(audioURL: URL) async throws -> TranscriptResult
    func transcribeSession(audioURL: URL) async throws -> TranscriptResult
}

extension CandyCornTranscriber {
    func availability(for locale: Locale) async -> LocalModelAvailability {
        _ = locale.identifier
        return .unavailableOnDevice
    }
}

protocol CandyCornDiarizer: Sendable {
    var id: String { get }
    func diarize(
        audioURL: URL,
        progress: @escaping @Sendable (DiarizationProgress) -> Void
    ) async throws -> DiarizationResult
}

protocol CandyCornSessionSummarizer: Sendable {
    var id: String { get }
    func summarizeSession(_ input: StructuredSessionSummaryInput) async throws -> StructuredSessionSummaryResult
}

protocol SessionProcessing: Sendable {
    func status(for appointmentID: UUID) async -> SessionProcessingRecord?
    func beginOrResume(appointmentID: UUID) async
    func resumePending() async
    func retry(appointmentID: UUID) async
    func noteSummaryStarted(appointmentID: UUID) async throws
    func noteSummaryCompleted(appointmentID: UUID, artifactID: UUID) async throws
    func events() async -> AsyncStream<SessionProcessingRecord>
}

protocol CandyCornVisionReader: Sendable {
    var id: String { get }
    func extractText(from input: VisionReadInput) async throws -> VisionReadResult
}

protocol DistressSupportClassifier: Sendable {
    var id: String { get }
    func classify(_ input: DistressClassificationInput) async -> DistressAssessment
}

protocol OpenRouterAPIKeyProviding: Sendable {
    func readKey() throws -> String?
    func storeKey(_ value: String) throws
    func removeKey() throws
    func hasKey() throws -> Bool
}

protocol AIConfigurationProviding: Sendable {
    func load() -> AIModelConfiguration
    func save(_ configuration: AIModelConfiguration) throws
    func reset() throws
}

protocol AIHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

protocol AIBackoffSleeping: Sendable {
    func sleep(for duration: Duration) async throws
}

enum AISendAction: Hashable, Sendable {
    case rewriteJournal(UUID)
    case summarizeJournal(UUID)
    case extractJournalSignals(UUID)
    case readPhoto(journalID: UUID, attachmentID: UUID)
    case summarizeSession(UUID)
    case generateAppointmentBrief(Appointment.Kind)
    case summarizeProcessedSession(UUID)
}

struct OutgoingSourceDescriptor: Equatable, Sendable, Identifiable {
    enum Kind: String, Sendable { case text, image }
    let id: UUID
    let kind: Kind
    let title: String
    let characterCount: Int
    let imageCount: Int
}

struct WhatLeavesDeviceSummary: Equatable, Sendable {
    let purpose: String
    let destination: String
    let sources: [OutgoingSourceDescriptor]
    let totalCharacterCount: Int
    let totalImageCount: Int
    let omittedSourceCount: Int
}

struct PendingAISend: Equatable, Sendable, Identifiable {
    let id: UUID
    let action: AISendAction
    let sourceRevision: Date?
    let disclosure: WhatLeavesDeviceSummary
}

enum AIProcessingState: Equatable, Sendable {
    case idle
    case processing
    case succeeded
    case failed(String)
}

enum AIProviderError: Error, Equatable, Sendable {
    case missingKey
    case invalidInput
    case unauthorized
    case rateLimited
    case requestRejected
    case serviceUnavailable
    case timedOut
    case invalidResponse
    case responseTooLarge
    case unsupportedOutput
    case unavailable

    var userMessage: String {
        switch self {
        case .missingKey: "Add an OpenRouter key in Settings before sending."
        case .unauthorized: "OpenRouter did not accept this key. Check it in Settings."
        case .rateLimited: "OpenRouter is busy. Try again shortly."
        case .timedOut: "AI processing took too long. Try again."
        case .unavailable, .serviceUnavailable: "AI processing is not available right now. Try again later."
        case .invalidInput: "This source cannot be sent for AI processing."
        case .responseTooLarge, .invalidResponse, .unsupportedOutput, .requestRejected:
            "Candy Corn could not use the AI response. Your source is unchanged."
        }
    }
}

enum AIEventName: String, Sendable {
    case requestCompleted
}

struct AIEventMetrics: Equatable, Sendable {
    let durationMilliseconds: Int
    let attemptCount: Int
    let promptTokens: Int?
    let completionTokens: Int?
    let reasoningTokens: Int?
    let totalTokens: Int?
    let costCredits: Double?
    let providerID: String
    let modelID: String
    let success: Bool
}

protocol AIEventLogging: Sendable {
    func record(_ name: AIEventName, metrics: AIEventMetrics)
}

protocol AIMonotonicClock: Sendable {
    func nowNanoseconds() -> UInt64
}
