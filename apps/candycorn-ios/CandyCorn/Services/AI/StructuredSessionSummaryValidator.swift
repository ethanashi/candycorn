import Foundation

struct StructuredSessionSummaryValidator: Sendable {
    private static let maximumSegments = 100_000
    private static let maximumTalkingPoints = 64
    private static let maximumSections = 18
    private static let maximumItems = 32
    private static let maximumEvidence = 8
    private static let maximumTextCharacters = 8_000
    private static let maximumQuoteCharacters = 2_000

    func validateInput(_ input: StructuredSessionSummaryInput) throws {
        guard !input.transcript.isEmpty, input.transcript.count <= Self.maximumSegments,
              input.openTalkingPoints.count <= Self.maximumTalkingPoints else {
            throw AIProviderError.invalidInput
        }
        guard Set(input.transcript.map(\.id)).count == input.transcript.count,
              Set(input.openTalkingPoints.map(\.id)).count == input.openTalkingPoints.count else {
            throw AIProviderError.invalidInput
        }
        for source in input.transcript {
            guard source.startMilliseconds >= 0, source.endMilliseconds > source.startMilliseconds,
                  isBoundedText(source.text, maximum: 50_000) else {
                throw AIProviderError.invalidInput
            }
        }
        for point in input.openTalkingPoints {
            guard isBoundedText(point.text, maximum: Self.maximumTextCharacters) else {
                throw AIProviderError.invalidInput
            }
        }
    }

    func validate(_ payload: StructuredSessionSummaryPayload, for input: StructuredSessionSummaryInput) throws {
        guard payload.template == input.template, (3...5).contains(payload.debriefTopics.count),
              payload.sections.count <= Self.maximumSections,
              payload.discussedTalkingPoints.count <= Self.maximumTalkingPoints else {
            throw AIProviderError.invalidResponse
        }
        let sourceMap = Dictionary(uniqueKeysWithValues: input.transcript.map { ($0.id, $0) })
        let sourceText = input.transcript.map(\.text).joined(separator: "\n").lowercased()
        var itemIDs = Set<UUID>()
        try validateItems(
            payload.debriefTopics, kind: nil, sourceMap: sourceMap,
            template: input.template, maximumItems: 5, itemIDs: &itemIDs
        )
        try validateSections(
            payload.sections, template: input.template, sourceMap: sourceMap,
            sourceText: sourceText, itemIDs: &itemIDs
        )
        try validateDiscussedTalkingPoints(
            payload.discussedTalkingPoints, input: input, sourceMap: sourceMap,
            itemIDs: &itemIDs
        )
    }

    private func validateSections(
        _ sections: [StructuredSessionSummarySection],
        template: SessionSummaryTemplate,
        sourceMap: [UUID: SessionTranscriptSource],
        sourceText: String,
        itemIDs: inout Set<UUID>
    ) throws {
        guard Set(sections.map(\.id)).count == sections.count else { throw AIProviderError.invalidResponse }
        let allowed = Self.allowedKindNames(for: template)
        for section in sections {
            guard allowed.contains(section.kind.rawValue), section.items.count <= Self.maximumItems,
                  isBoundedText(section.title, maximum: 240) else {
                throw AIProviderError.invalidResponse
            }
            try validateSafety(section.title, template: template, sourceText: sourceText)
            try validateItems(
                section.items, kind: section.kind, sourceMap: sourceMap,
                template: template, maximumItems: Self.maximumItems, itemIDs: &itemIDs
            )
        }
    }

    private func validateItems(
        _ items: [StructuredSessionSummaryItem],
        kind: SessionSummarySectionKind?,
        sourceMap: [UUID: SessionTranscriptSource],
        template: SessionSummaryTemplate,
        maximumItems: Int,
        itemIDs: inout Set<UUID>
    ) throws {
        guard maximumItems > 0, items.count <= maximumItems else { throw AIProviderError.invalidResponse }
        for item in items {
            guard itemIDs.insert(item.id).inserted,
                  isBoundedText(item.text, maximum: Self.maximumTextCharacters),
                  !item.evidence.isEmpty, item.evidence.count <= Self.maximumEvidence else {
                throw AIProviderError.invalidResponse
            }
            let citedSources = try validateEvidence(item.evidence, sourceMap: sourceMap, output: item.text)
            try validateProvenance(item, kind: kind, citedSources: citedSources)
            let evidenceText = item.evidence.map(\.quote).joined(separator: "\n").lowercased()
            try validateSafety(item.text, template: template, sourceText: evidenceText)
        }
    }

    private func validateEvidence(
        _ evidence: [EvidenceCitation],
        sourceMap: [UUID: SessionTranscriptSource],
        output: String
    ) throws -> [SessionTranscriptSource] {
        var citedSources: [SessionTranscriptSource] = []
        citedSources.reserveCapacity(min(evidence.count, Self.maximumEvidence))
        for citation in evidence {
            guard let source = sourceMap[citation.sourceID],
                  isBoundedText(citation.quote, maximum: Self.maximumQuoteCharacters),
                  source.text.contains(citation.quote),
                  let timestamp = citation.timestampMilliseconds,
                  timestamp >= source.startMilliseconds, timestamp <= source.endMilliseconds else {
                throw AIProviderError.invalidResponse
            }
            try validateUncertainty(sourceQuote: citation.quote, output: output)
            citedSources.append(source)
        }
        return citedSources
    }

    private func validateProvenance(
        _ item: StructuredSessionSummaryItem,
        kind: SessionSummarySectionKind?,
        citedSources: [SessionTranscriptSource]
    ) throws {
        let output = item.text.lowercased()
        let providerClaim = Self.providerClaimMarkers.contains(where: output.contains)
        let providerKind = kind == .homework || kind == .providerInstructions
            || kind == .providerObservations || kind == .triggersOrProvocations
        if providerClaim || providerKind {
            guard item.provenance == .provider,
                  citedSources.allSatisfy({ $0.speaker == .provider }) else {
                throw AIProviderError.invalidResponse
            }
        }
        switch item.provenance {
        case .provider:
            guard citedSources.allSatisfy({ $0.speaker == .provider }) else {
                throw AIProviderError.invalidResponse
            }
        case .patient:
            guard citedSources.allSatisfy({ $0.speaker == .patient }) else {
                throw AIProviderError.invalidResponse
            }
        case .candyCorn:
            if kind == .homework || kind == .providerInstructions {
                throw AIProviderError.invalidResponse
            }
        }
        if kind == .goals, citedSources.contains(where: { $0.speaker == .provider }) {
            guard item.provenance == .provider,
                  citedSources.allSatisfy({ $0.speaker == .provider }) else {
                throw AIProviderError.invalidResponse
            }
        }
    }

    private func validateDiscussedTalkingPoints(
        _ items: [StructuredSessionSummaryItem],
        input: StructuredSessionSummaryInput,
        sourceMap: [UUID: SessionTranscriptSource],
        itemIDs: inout Set<UUID>
    ) throws {
        let talkingPointIDs = Set(input.openTalkingPoints.map(\.id))
        try validateItems(
            items, kind: nil, sourceMap: sourceMap, template: input.template,
            maximumItems: Self.maximumTalkingPoints,
            itemIDs: &itemIDs
        )
        for item in items {
            guard let relatedID = item.relatedEntityID, talkingPointIDs.contains(relatedID) else {
                throw AIProviderError.invalidResponse
            }
        }
    }

    private func validateSafety(
        _ text: String,
        template: SessionSummaryTemplate,
        sourceText: String
    ) throws {
        let output = text.lowercased()
        for term in Self.diagnosisTerms where output.contains(term) && !sourceText.contains(term) {
            throw AIProviderError.invalidResponse
        }
        for phrase in Self.motivePhrases where output.contains(phrase) && !sourceText.contains(phrase) {
            throw AIProviderError.invalidResponse
        }
        if Self.containsTreatmentChange(output) && !Self.containsTreatmentChange(sourceText) {
            throw AIProviderError.invalidResponse
        }
        if template == .tms {
            guard !Self.containsTMSCausation(output), !Self.containsTreatmentChange(output) else {
                throw AIProviderError.invalidResponse
            }
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

    private func isBoundedText(_ text: String, maximum: Int) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return maximum > 0 && !trimmed.isEmpty && trimmed.count <= maximum
    }

    private static func allowedKindNames(for template: SessionSummaryTemplate) -> Set<String> {
        switch template {
        case .therapy:
            return Set([
                SessionSummarySectionKind.mainTopics.rawValue,
                SessionSummarySectionKind.patientRealizations.rawValue,
                SessionSummarySectionKind.providerObservations.rawValue,
                SessionSummarySectionKind.homework.rawValue,
                SessionSummarySectionKind.goals.rawValue,
                SessionSummarySectionKind.beliefsOrStuckPoints.rawValue,
                SessionSummarySectionKind.copingTools.rawValue,
                SessionSummarySectionKind.questionsToRevisit.rawValue,
                SessionSummarySectionKind.unfinishedTopics.rawValue,
                SessionSummarySectionKind.nextSessionItems.rawValue,
            ])
        case .tms:
            return Set([
                SessionSummarySectionKind.currentFeelingsBeforeSession.rawValue,
                SessionSummarySectionKind.distressOrAnxiety.rawValue,
                SessionSummarySectionKind.triggersOrProvocations.rawValue,
                SessionSummarySectionKind.questionsForProvider.rawValue,
                SessionSummarySectionKind.providerInstructions.rawValue,
                SessionSummarySectionKind.changesDiscussed.rawValue,
                SessionSummarySectionKind.feelingsAfterSession.rawValue,
                SessionSummarySectionKind.thingsToMonitor.rawValue,
                SessionSummarySectionKind.nextSessionItems.rawValue,
            ])
        }
    }

    private static func containsTreatmentChange(_ text: String) -> Bool {
        let hasTreatment = treatmentTerms.contains(where: text.contains)
        let hasChange = treatmentChangeTerms.contains(where: text.contains)
        return hasTreatment && hasChange
    }

    private static func containsTMSCausation(_ text: String) -> Bool {
        let hasTreatment = tmsTerms.contains(where: text.contains)
        let hasCausation = causationTerms.contains(where: text.contains)
        return hasTreatment && hasCausation
    }

    private static let uncertaintyMarkers = [
        "i think", "i don't know", "i do not know", "i'm not sure", "i am not sure",
        "maybe", "might", "possibly", "probably", "i guess", "i wonder",
        "unclear", "seems", "appears",
    ]
    // nyx: These bounded phrase gates reject high-risk unsupported additions. A future local entailment model can widen recall without trusting organizer output.
    private static let diagnosisTerms = [
        "ptsd", "post-traumatic stress", "bipolar", "ocd", "diagnosis", "depression",
        "major depressive disorder", "personality disorder", "psychotic", "narcissist",
        "adhd", "borderline personality", "autism spectrum",
    ]
    private static let motivePhrases = [
        "to intimidate", "wanted to hurt", "wanted to control", "intended to",
        "trying to manipulate", "because he wanted", "because she wanted", "because they wanted",
    ]
    private static let providerClaimMarkers = [
        "provider said", "provider asked", "provider noted", "provider observed",
        "therapist said", "therapist asked", "clinician said", "doctor said",
    ]
    private static let treatmentTerms = [
        "medication", "medicine", "dose", "dosage", "treatment", "stimulation", "protocol",
    ]
    private static let treatmentChangeTerms = [
        "increase", "decrease", "reduce", "lower", "raise", "stop", "start", "change",
        "adjust", "switch", "recommend", "should",
    ]
    private static let tmsTerms = ["tms", "stimulation", "treatment"]
    private static let causationTerms = [
        "caused", "improved", "reduced", "made me", "made the", "because of", "led to", "resulted in",
    ]
}
