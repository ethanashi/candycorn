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

struct AppointmentBriefInput: Codable, Equatable, Sendable {
    let appointmentKind: Appointment.Kind
    let sources: [SourceTextDocument]
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
    func transcribeJournal(audioURL: URL) async throws -> TranscriptResult
    func transcribeSession(audioURL: URL) async throws -> TranscriptResult
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
