import Foundation

struct OrganizerOutputValidator: Sendable {
    private static let maximumSources = 64
    private static let maximumItems = 32
    private static let maximumEvidenceItems = 8
    private static let maximumTextCharacters = 8_000
    private static let maximumEvidenceCharacters = 2_000

    func validateInputSources(_ sources: [SourceTextDocument]) throws {
        try validateSources(sources)
    }

    func validateRewrite(_ segments: [RewriteSegment], unclearAreas: [String], source: SourceTextDocument) throws {
        try validateSources([source])
        guard !segments.isEmpty, segments.count <= Self.maximumItems, unclearAreas.count <= Self.maximumItems else {
            throw AIProviderError.invalidResponse
        }
        for segment in segments {
            try validateStatement(text: segment.text, evidence: segment.evidence, sources: [source])
        }
        try validateStrings(unclearAreas, maximumCharacters: 1_000, sources: [source])
    }

    func validateSummary(_ statements: [EvidenceBackedStatement], sources: [SourceTextDocument]) throws {
        try validateSources(sources)
        guard !statements.isEmpty, statements.count <= Self.maximumItems else {
            throw AIProviderError.invalidResponse
        }
        for statement in statements {
            try validateStatement(text: statement.text, evidence: statement.evidence, sources: sources)
        }
    }

    func validateSession(_ sections: [SessionSummarySection], source: SourceTextDocument) throws {
        try validateSources([source])
        guard !sections.isEmpty, sections.count <= Self.maximumItems else { throw AIProviderError.invalidResponse }
        for section in sections {
            try validateText(section.title, maximumCharacters: 240, sources: [source])
            try validateSummary(section.statements, sources: [source])
        }
    }

    func validateBrief(_ sections: [AppointmentBriefSection], sources: [SourceTextDocument]) throws {
        try validateSources(sources)
        guard !sections.isEmpty, sections.count <= Self.maximumItems else { throw AIProviderError.invalidResponse }
        for section in sections {
            try validateText(section.title, maximumCharacters: 240, sources: sources)
            try validateSummary(section.statements, sources: sources)
        }
    }

    func validateGoalProgressInput(_ input: GoalProgressSuggestionInput) throws {
        guard input.originID == input.origin.sourceID,
              !input.sources.isEmpty, input.sources.count <= 128,
              !input.goals.isEmpty, input.goals.count <= 64,
              Set(input.sources.map(\.id)).count == input.sources.count,
              Set(input.goals.map(\.id)).count == input.goals.count,
              !input.requestText.isEmpty, input.requestText.count <= 50_000 else {
            throw AIProviderError.invalidInput
        }
        try validateSources(input.sources.map(\.document))
        for source in input.sources {
            let pairedBounds = source.startMilliseconds != nil && source.endMilliseconds != nil
            let journalBounds = source.startMilliseconds == nil && source.endMilliseconds == nil
            guard pairedBounds || journalBounds else { throw AIProviderError.invalidInput }
            if let start = source.startMilliseconds, let end = source.endMilliseconds {
                guard start >= 0, end > start else { throw AIProviderError.invalidInput }
            }
        }
        for goal in input.goals {
            let title = goal.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= 240, (goal.detail?.count ?? 0) <= 1_000 else {
                throw AIProviderError.invalidInput
            }
        }
    }

    func validatedGoalProgressSuggestions(
        _ suggestions: [GoalProgressSuggestion],
        input: GoalProgressSuggestionInput
    ) throws -> [GoalProgressSuggestion] {
        try validateGoalProgressInput(input)
        guard !suggestions.isEmpty, suggestions.count <= 16,
              Set(suggestions.map(\.id)).count == suggestions.count,
              Set(suggestions.map(\.goalID)).count == suggestions.count else {
            throw AIProviderError.invalidResponse
        }
        let goals = Dictionary(uniqueKeysWithValues: input.goals.map { ($0.id, $0) })
        let sources = Dictionary(uniqueKeysWithValues: input.sources.map { ($0.id, $0) })
        for suggestion in suggestions {
            guard goals[suggestion.goalID] != nil,
                  !suggestion.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  suggestion.note.count <= 1_000,
                  !suggestion.evidence.isEmpty, suggestion.evidence.count <= Self.maximumEvidenceItems else {
                throw AIProviderError.invalidResponse
            }
            try validateGoalProgressEvidence(suggestion, sources: sources)
            try validateText(suggestion.note, maximumCharacters: 1_000, sources: input.sources.map(\.document))
            try validateNoTreatmentRecommendation(suggestion.note)
        }
        return suggestions
            .map {
                GoalProgressSuggestion(
                    id: $0.id, goalID: $0.goalID, mark: $0.mark,
                    note: $0.note, evidence: $0.evidence, resolution: .pending
                )
            }
            .sorted {
                let left = goals[$0.goalID]?.title.lowercased() ?? ""
                let right = goals[$1.goalID]?.title.lowercased() ?? ""
                return left == right ? $0.goalID.uuidString < $1.goalID.uuidString : left < right
            }
    }

    func validateSignals(_ signals: JournalSignals, source: SourceTextDocument) throws {
        try validateSources([source])
        try validateText(signals.summary, sources: [source])
        guard signals.emotions.count <= Self.maximumItems,
              signals.explicitCommitments.count <= Self.maximumItems,
              signals.talkingPointSuggestions.count <= Self.maximumItems,
              signals.possibleThemes.count <= Self.maximumItems else {
            throw AIProviderError.invalidResponse
        }
        try validateEvidenceItems(signals.emotions, source: source)
        try validateEvidenceItems(signals.possibleThemes, source: source)
        for commitment in signals.explicitCommitments {
            try validateText(commitment.text, sources: [source])
            if let cadence = commitment.cadenceHint {
                try validateText(cadence, maximumCharacters: 240, sources: [source])
            }
            try validateVerbatim(commitment.evidence, source: source)
            guard Self.isExplicitCommitment(commitment.evidence) else { throw AIProviderError.invalidResponse }
        }
        for suggestion in signals.talkingPointSuggestions {
            try validateText(suggestion.text, sources: [source])
            try validateText(suggestion.reason, sources: [source])
            try validateVerbatim(suggestion.evidence, source: source)
        }
    }

    func validateVision(text: String, uncertainSpans: [String]) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= Self.maximumTextCharacters,
              uncertainSpans.count <= Self.maximumItems else {
            throw AIProviderError.invalidResponse
        }
        for span in uncertainSpans {
            let trimmed = span.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= Self.maximumEvidenceCharacters, text.contains(trimmed) else {
                throw AIProviderError.invalidResponse
            }
        }
    }

    private func validateEvidenceItems(_ items: [JournalSignals.EvidenceItem], source: SourceTextDocument) throws {
        for item in items {
            try validateText(item.label, maximumCharacters: 1_000, sources: [source])
            try validateVerbatim(item.evidence, source: source)
        }
    }

    private func validateGoalProgressEvidence(
        _ suggestion: GoalProgressSuggestion,
        sources: [UUID: GoalProgressSourceDocument]
    ) throws {
        var combinedEvidence = ""
        for citation in suggestion.evidence {
            guard let source = sources[citation.sourceID],
                  !source.document.title.lowercased().hasPrefix("unknown speaker") else {
                throw AIProviderError.invalidResponse
            }
            try validateVerbatim(citation.quote, source: source.document)
            try validateUncertainty(sourceQuote: citation.quote, output: suggestion.note)
            if let start = source.startMilliseconds, let end = source.endMilliseconds {
                guard let timestamp = citation.timestampMilliseconds,
                      (start...end).contains(timestamp) else {
                    throw AIProviderError.invalidResponse
                }
            } else if citation.timestampMilliseconds != nil {
                throw AIProviderError.invalidResponse
            }
            combinedEvidence += " " + citation.quote.lowercased()
        }
        if suggestion.mark == .doneToday {
            guard Self.isExplicitCompletion(combinedEvidence) else { throw AIProviderError.invalidResponse }
        }
    }

    private func validateNoTreatmentRecommendation(_ text: String) throws {
        let normalized = text.lowercased()
        guard !Self.treatmentRecommendationPhrases.contains(where: normalized.contains) else {
            throw AIProviderError.invalidResponse
        }
    }

    private func validateStatement(
        text: String,
        evidence: [EvidenceCitation],
        sources: [SourceTextDocument]
    ) throws {
        try validateText(text, sources: sources)
        guard !evidence.isEmpty, evidence.count <= Self.maximumEvidenceItems else {
            throw AIProviderError.invalidResponse
        }
        let sourceMap = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        for citation in evidence {
            guard let source = sourceMap[citation.sourceID] else { throw AIProviderError.invalidResponse }
            try validateVerbatim(citation.quote, source: source)
            try validateUncertainty(sourceQuote: citation.quote, output: text)
        }
    }

    private func validateSources(_ sources: [SourceTextDocument]) throws {
        guard !sources.isEmpty, sources.count <= Self.maximumSources, Set(sources.map(\.id)).count == sources.count else {
            throw AIProviderError.invalidInput
        }
        var totalCharacters = 0
        for source in sources {
            guard !source.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  source.text.count <= 50_000,
                  !source.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  source.title.count <= 240 else {
                throw AIProviderError.invalidInput
            }
            totalCharacters += source.text.count
            guard totalCharacters <= 50_000 else { throw AIProviderError.invalidInput }
        }
    }

    private func validateStrings(
        _ values: [String],
        maximumCharacters: Int,
        sources: [SourceTextDocument]
    ) throws {
        for value in values {
            try validateText(value, maximumCharacters: maximumCharacters, sources: sources)
        }
    }

    private func validateText(
        _ text: String,
        maximumCharacters: Int = Self.maximumTextCharacters,
        sources: [SourceTextDocument]
    ) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard maximumCharacters > 0, !trimmed.isEmpty, trimmed.count <= maximumCharacters else {
            throw AIProviderError.invalidResponse
        }
        let sourceText = sources.map(\.text).joined(separator: "\n").lowercased()
        let output = trimmed.lowercased()
        for term in Self.diagnosisTerms where output.contains(term) && !sourceText.contains(term) {
            throw AIProviderError.invalidResponse
        }
        for phrase in Self.motivePhrases where output.contains(phrase) && !sourceText.contains(phrase) {
            throw AIProviderError.invalidResponse
        }
    }

    private func validateVerbatim(_ quote: String, source: SourceTextDocument) throws {
        let trimmed = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= Self.maximumEvidenceCharacters, source.text.contains(trimmed) else {
            throw AIProviderError.invalidResponse
        }
    }

    private func validateUncertainty(sourceQuote: String, output: String) throws {
        let source = sourceQuote.lowercased()
        guard Self.uncertaintyMarkers.contains(where: source.contains) else { return }
        let generated = output.lowercased()
        guard Self.uncertaintyMarkers.contains(where: generated.contains) else {
            throw AIProviderError.invalidResponse
        }
    }

    private static func isExplicitCommitment(_ evidence: String) -> Bool {
        let text = evidence.lowercased()
        if optionalCommitmentMarkers.contains(where: text.contains) { return false }
        return explicitCommitmentMarkers.contains(where: text.contains)
    }

    private static func isExplicitCompletion(_ evidence: String) -> Bool {
        guard !optionalCommitmentMarkers.contains(where: evidence.contains) else { return false }
        return completionMarkers.contains(where: evidence.contains)
    }

    private static let uncertaintyMarkers = [
        "i think", "i don't remember", "i do not remember", "maybe", "might", "possibly", "not sure", "unclear",
    ]
    private static let optionalCommitmentMarkers = ["maybe", "might", "could", "should", "consider"]
    private static let explicitCommitmentMarkers = [
        "i'm going to", "i am going to", "i will", "i plan to", "i want to",
        "i'd like you to", "i would like you to", "your homework", "please ",
    ]
    private static let completionMarkers = [
        "i completed", "i finished", "i did ", "i went ", "i made it", "i followed through",
        "completed today", "finished today", "done today",
    ]
    private static let treatmentRecommendationPhrases = [
        "you should change", "you should stop", "stop taking", "start taking", "increase the dose",
        "decrease the dose", "change medication", "change treatment", "treatment should",
    ]
    // nyx: This bounded phrase gate catches deterministic fixture failures. A future local evaluator can widen it without making organizer output authoritative.
    private static let diagnosisTerms = [
        "ptsd", "post-traumatic stress", "bipolar", "ocd", "diagnosis", "clinical depression",
        "personality disorder", "psychotic", "narcissist", "adhd",
    ]
    private static let motivePhrases = [
        "to intimidate", "wanted to hurt", "wanted to control", "intended to", "trying to manipulate",
        "because he wanted", "because she wanted", "because they wanted",
    ]
}
