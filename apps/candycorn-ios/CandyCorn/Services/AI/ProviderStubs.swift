import Foundation

struct UnavailableTranscriber: CandyCornTranscriber {
    let id = "unavailable-transcriber"

    func transcribeJournal(audioURL: URL) async throws -> TranscriptResult {
        guard audioURL.isFileURL else { throw AIProviderError.invalidInput }
        throw AIProviderError.unavailable
    }

    func transcribeSession(audioURL: URL) async throws -> TranscriptResult {
        guard audioURL.isFileURL else { throw AIProviderError.invalidInput }
        throw AIProviderError.unavailable
    }
}

struct AppleFoundationModelProvider: CandyCornLanguageModel {
    let id = "apple-foundation-model-unavailable"

    func rewriteJournal(_ input: RewriteJournalInput) async throws -> RewriteJournalResult {
        guard !input.source.text.isEmpty else { throw AIProviderError.invalidInput }
        throw AIProviderError.unavailable
    }

    func summarizeJournal(_ input: JournalSummaryInput) async throws -> JournalSummaryResult {
        guard !input.source.text.isEmpty else { throw AIProviderError.invalidInput }
        throw AIProviderError.unavailable
    }

    func extractJournalSignals(_ input: JournalSignalInput) async throws -> JournalSignalResult {
        guard !input.source.text.isEmpty else { throw AIProviderError.invalidInput }
        throw AIProviderError.unavailable
    }

    func summarizeSession(_ input: SessionSummaryInput) async throws -> SessionSummaryResult {
        guard !input.manualNotes.text.isEmpty else { throw AIProviderError.invalidInput }
        throw AIProviderError.unavailable
    }

    func generateAppointmentBrief(_ input: AppointmentBriefInput) async throws -> AppointmentBriefResult {
        guard !input.sources.isEmpty else { throw AIProviderError.invalidInput }
        throw AIProviderError.unavailable
    }
}

struct NoOpDistressSupportClassifier: DistressSupportClassifier {
    let id = "no-op-distress-support"

    func classify(_ input: DistressClassificationInput) async -> DistressAssessment {
        _ = input.sourceID
        _ = input.text.count
        return DistressAssessment(level: .normal, evidenceSpans: [], uncertainty: 1, suggestedUI: .none)
    }
}
