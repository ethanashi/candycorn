import Foundation

struct GoalProgressSuggestionWorkProduct: Equatable, Sendable {
    let artifact: AIArtifact
    let result: GoalProgressSuggestionResult
}

actor GoalProgressSuggester {
    private static let maximumSources = 128
    private static let maximumGoals = 64
    private static let maximumSourceCharacters = 2_000
    private static let maximumJournalCharacters = 12_000
    private let careStore: any CareStore
    private let languageModel: any CandyCornLanguageModel
    private let validator: OrganizerOutputValidator
    private let now: @Sendable () -> Date

    init(
        careStore: any CareStore,
        languageModel: any CandyCornLanguageModel,
        validator: OrganizerOutputValidator = OrganizerOutputValidator(),
        now: @escaping @Sendable () -> Date
    ) {
        self.careStore = careStore
        self.languageModel = languageModel
        self.validator = validator
        self.now = now
    }

    func prepareInput(from origin: GoalProgressSuggestionSource) async throws -> GoalProgressSuggestionInput {
        let snapshot = try await careStore.snapshot()
        return try Self.makeInput(from: origin, snapshot: snapshot)
    }

    func generate(_ input: GoalProgressSuggestionInput) async throws -> GoalProgressSuggestionWorkProduct {
        try validator.validateGoalProgressInput(input)
        guard input.requestText == (try Self.canonicalRequestText(origin: input.origin, sources: input.sources, goals: input.goals)) else {
            throw AIProviderError.invalidInput
        }
        let before = try await careStore.snapshot()
        let currentBefore = try Self.makeInput(from: input.origin, snapshot: before)
        guard currentBefore == input else { throw AIProviderError.invalidInput }
        if let existing = try existingProduct(for: input, artifacts: before.artifacts) { return existing }
        let providerResult = try await languageModel.suggestGoalProgress(input)
        let suggestions = try validator.validatedGoalProgressSuggestions(providerResult.suggestions, input: input)
        let snapshot = try await careStore.snapshot()
        let currentInput = try Self.makeInput(from: input.origin, snapshot: snapshot)
        guard currentInput == input else { throw AIProviderError.invalidInput }
        let metadata = providerResult.metadata
        let provider = metadata.provider.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = metadata.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !provider.isEmpty, !model.isEmpty else { throw AIProviderError.invalidResponse }
        let result = GoalProgressSuggestionResult(suggestions: suggestions, metadata: metadata)
        let payload = GoalProgressSuggestionArtifactPayload(origin: input.origin, input: input, result: result)
        let encoded = try Self.encode(payload)
        let sourceIDs = Self.artifactSourceIDs(origin: input.originID, suggestions: suggestions)
        let artifact = AIArtifact(
            id: UUID(), kind: .goalProgressSuggestions, sourceIDs: sourceIDs,
            provider: provider, model: model, structuredPayload: encoded, createdAt: now()
        )
        return GoalProgressSuggestionWorkProduct(artifact: artifact, result: result)
    }

    private func existingProduct(
        for input: GoalProgressSuggestionInput,
        artifacts: [AIArtifact]
    ) throws -> GoalProgressSuggestionWorkProduct? {
        guard artifacts.count <= 100_000 else { throw AIProviderError.invalidInput }
        let ordered = artifacts.filter { $0.kind == .goalProgressSuggestions }.sorted {
            ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString)
        }
        for artifact in ordered.prefix(1_024) {
            guard let payload = try? JSONDecoder().decode(
                GoalProgressSuggestionArtifactPayload.self,
                from: artifact.structuredPayload
            ), payload.origin == input.origin, payload.input == input else { continue }
            let validated = try validator.validatedGoalProgressSuggestions(payload.result.suggestions, input: input)
            guard Set(validated.map(\.id)) == Set(payload.result.suggestions.map(\.id)),
                  payload.result.metadata.provider == artifact.provider,
                  payload.result.metadata.model == artifact.model else {
                throw AIProviderError.invalidResponse
            }
            return GoalProgressSuggestionWorkProduct(artifact: artifact, result: payload.result)
        }
        return nil
    }

    static func makeInput(
        from origin: GoalProgressSuggestionSource,
        snapshot: CareSnapshot
    ) throws -> GoalProgressSuggestionInput {
        guard snapshot.goals.count <= 100_000, snapshot.journals.count <= 100_000,
              snapshot.appointments.count <= 100_000, snapshot.transcript.count <= 100_000 else {
            throw AIProviderError.invalidInput
        }
        let goals = try activeGoalContexts(snapshot.goals)
        let sources = try sourceDocuments(for: origin, snapshot: snapshot)
        let text = try canonicalRequestText(origin: origin, sources: sources, goals: goals)
        return GoalProgressSuggestionInput(
            originID: origin.sourceID, origin: origin, sources: sources, goals: goals, requestText: text
        )
    }

    private static func activeGoalContexts(_ values: [Goal]) throws -> [GoalProgressGoalContext] {
        let active = values.filter { $0.status == .active }.sorted(by: goalOrder)
        guard !active.isEmpty, active.count <= maximumGoals else { throw AIProviderError.invalidInput }
        return active.map { goal in
            GoalProgressGoalContext(
                id: goal.id,
                title: bounded(goal.title, maximum: 240),
                detail: goal.detail.map { bounded($0, maximum: 1_000) },
                cadence: goal.cadence
            )
        }
    }

    private static func sourceDocuments(
        for origin: GoalProgressSuggestionSource,
        snapshot: CareSnapshot
    ) throws -> [GoalProgressSourceDocument] {
        switch origin {
        case let .journal(id):
            guard let journal = snapshot.journals.first(where: { $0.id == id }) else {
                throw AIProviderError.invalidInput
            }
            let cleaned = journal.cleanedText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let raw = journal.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = cleaned.flatMap { $0.isEmpty ? nil : $0 } ?? raw
            guard !text.isEmpty else { throw AIProviderError.invalidInput }
            return [GoalProgressSourceDocument(
                document: SourceTextDocument(
                    id: journal.id, kind: .journal, title: bounded(journal.title, maximum: 240),
                    text: bounded(text, maximum: maximumJournalCharacters), occurredAt: journal.createdAt
                ),
                startMilliseconds: nil,
                endMilliseconds: nil
            )]
        case let .processedSession(id):
            return try processedSessionDocuments(id: id, snapshot: snapshot)
        }
    }

    private static func processedSessionDocuments(
        id: UUID,
        snapshot: CareSnapshot
    ) throws -> [GoalProgressSourceDocument] {
        guard let appointment = snapshot.appointments.first(where: { $0.id == id }),
              snapshot.sessionProcessing.contains(where: { $0.appointmentID == id && $0.stage == .ready }),
              let summaryID = appointment.summaryID,
              let summary = snapshot.artifacts.first(where: { $0.id == summaryID && $0.kind == .sessionSummary }),
              (try? JSONDecoder().decode(StructuredSessionSummaryResult.self, from: summary.structuredPayload)) != nil else {
            throw AIProviderError.invalidInput
        }
        let segments = snapshot.transcript.filter { $0.appointmentID == id }.sorted {
            ($0.startMilliseconds, $0.id.uuidString.lowercased())
                < ($1.startMilliseconds, $1.id.uuidString.lowercased())
        }
        guard !segments.isEmpty, segments.count <= maximumSources else { throw AIProviderError.invalidInput }
        return try segments.map { segment in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, segment.startMilliseconds >= 0,
                  segment.endMilliseconds > segment.startMilliseconds else {
                throw AIProviderError.invalidInput
            }
            return GoalProgressSourceDocument(
                document: SourceTextDocument(
                    id: segment.id,
                    kind: .sessionNotes,
                    title: "\(segment.speaker.goalProgressTitle) transcript segment",
                    text: bounded(text, maximum: maximumSourceCharacters),
                    occurredAt: appointment.endedAt ?? appointment.startedAt ?? appointment.scheduledAt
                ),
                startMilliseconds: segment.startMilliseconds,
                endMilliseconds: segment.endMilliseconds
            )
        }
    }

    static func canonicalRequestText(
        origin: GoalProgressSuggestionSource,
        sources: [GoalProgressSourceDocument],
        goals: [GoalProgressGoalContext]
    ) throws -> String {
        let payload = GoalProgressRequestPayload(origin: origin, sources: sources, goals: goals)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        guard !data.isEmpty, data.count <= 50_000, let text = String(data: data, encoding: .utf8) else {
            throw AIProviderError.invalidInput
        }
        return text
    }

    private static func artifactSourceIDs(
        origin: UUID,
        suggestions: [GoalProgressSuggestion]
    ) -> [UUID] {
        var seen: Set<UUID> = []
        var values: [UUID] = []
        for id in [origin] + suggestions.flatMap({ [$0.goalID] + $0.evidence.map(\.sourceID) }).prefix(1_024) {
            if seen.insert(id).inserted { values.append(id) }
        }
        return values
    }

    private static func encode<Payload: Encodable>(_ payload: Payload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        guard !data.isEmpty else { throw AIProviderError.invalidResponse }
        return data
    }

    private static func goalOrder(_ left: Goal, _ right: Goal) -> Bool {
        let leftTitle = left.title.lowercased()
        let rightTitle = right.title.lowercased()
        return leftTitle == rightTitle
            ? left.id.uuidString.lowercased() < right.id.uuidString.lowercased()
            : leftTitle < rightTitle
    }

    private static func bounded(_ value: String, maximum: Int) -> String {
        String(value.prefix(maximum))
    }
}

struct GoalProgressResolutionPlan: Sendable {
    let artifact: AIArtifact?
    let progress: GoalProgress?

    static func make(
        snapshot: CareSnapshot,
        suggestionID: UUID,
        resolution: GoalProgressSuggestionResolution,
        now: Date
    ) throws -> GoalProgressResolutionPlan {
        guard resolution != .pending, snapshot.artifacts.count <= 100_000,
              snapshot.goals.count <= 100_000, snapshot.goalProgress.count <= 100_000 else {
            throw VaultRepositoryError.invalidInput
        }
        let matches = readableMatches(in: snapshot.artifacts, suggestionID: suggestionID)
        guard matches.count == 1, let match = matches.first else { throw VaultRepositoryError.invalidInput }
        let suggestion = match.payload.result.suggestions[match.index]
        let existing = snapshot.goalProgress.first { $0.id == suggestionID }
        if suggestion.resolution == resolution {
            try validateResolved(suggestion, origin: match.payload.origin, existing: existing)
            return GoalProgressResolutionPlan(artifact: nil, progress: nil)
        }
        guard suggestion.resolution == .pending,
              match.payload.origin == match.payload.input.origin,
              match.payload.input.originID == match.payload.origin.sourceID,
              match.payload.result.metadata.provider == match.artifact.provider,
              match.payload.result.metadata.model == match.artifact.model,
              match.artifact.sourceIDs.first == match.payload.origin.sourceID,
              match.artifact.sourceIDs.contains(suggestion.goalID),
              suggestion.evidence.allSatisfy({ match.artifact.sourceIDs.contains($0.sourceID) }),
              let goal = snapshot.goals.first(where: { $0.id == suggestion.goalID }), goal.status == .active else {
            throw VaultRepositoryError.invalidInput
        }
        let validated = try? OrganizerOutputValidator().validatedGoalProgressSuggestions(
            match.payload.result.suggestions,
            input: match.payload.input
        )
        guard validated?.contains(where: { $0.id == suggestionID }) == true,
              (try? GoalProgressSuggester.makeInput(from: match.payload.origin, snapshot: snapshot)) == match.payload.input else {
            throw VaultRepositoryError.invalidInput
        }
        let proposed = resolution == .accepted
            ? makeProgress(suggestion, origin: match.payload.origin, now: now)
            : nil
        if let existing {
            guard let proposed, equivalent(existing, proposed) else { throw VaultRepositoryError.invalidInput }
        }
        var payload = match.payload
        payload.result.suggestions[match.index].resolution = resolution
        let encoded = try encode(payload)
        let replacement = AIArtifact(
            id: match.artifact.id, kind: match.artifact.kind, sourceIDs: match.artifact.sourceIDs,
            provider: match.artifact.provider, model: match.artifact.model,
            structuredPayload: encoded, createdAt: match.artifact.createdAt
        )
        return GoalProgressResolutionPlan(artifact: replacement, progress: existing == nil ? proposed : nil)
    }

    private struct Match {
        let artifact: AIArtifact
        var payload: GoalProgressSuggestionArtifactPayload
        let index: Int
    }

    private static func readableMatches(in artifacts: [AIArtifact], suggestionID: UUID) -> [Match] {
        var matches: [Match] = []
        for artifact in artifacts.prefix(100_000) where artifact.kind == .goalProgressSuggestions {
            guard let payload = try? JSONDecoder().decode(
                GoalProgressSuggestionArtifactPayload.self,
                from: artifact.structuredPayload
            ) else { continue }
            for index in payload.result.suggestions.indices.prefix(16)
                where payload.result.suggestions[index].id == suggestionID {
                matches.append(Match(artifact: artifact, payload: payload, index: index))
            }
        }
        return matches
    }

    private static func validateResolved(
        _ suggestion: GoalProgressSuggestion,
        origin: GoalProgressSuggestionSource,
        existing: GoalProgress?
    ) throws {
        if suggestion.resolution == .dismissed {
            guard existing == nil else { throw VaultRepositoryError.invalidInput }
            return
        }
        let expected = makeProgress(suggestion, origin: origin, now: existing?.createdAt ?? .distantPast)
        guard let existing, equivalent(existing, expected) else { throw VaultRepositoryError.invalidInput }
    }

    private static func makeProgress(
        _ suggestion: GoalProgressSuggestion,
        origin: GoalProgressSuggestionSource,
        now: Date
    ) -> GoalProgress {
        GoalProgress(
            id: suggestion.id,
            goalID: suggestion.goalID,
            sourceEntryID: origin.journalID,
            note: suggestion.note,
            source: .aiSuggestedProgress,
            createdAt: now,
            mark: suggestion.mark
        )
    }

    private static func equivalent(_ left: GoalProgress, _ right: GoalProgress) -> Bool {
        left.id == right.id && left.goalID == right.goalID
            && left.sourceEntryID == right.sourceEntryID && left.note == right.note
            && left.source == right.source && left.mark == right.mark
    }

    private static func encode(_ payload: GoalProgressSuggestionArtifactPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(payload)
        } catch {
            throw VaultRepositoryError.invalidInput
        }
    }
}

private struct GoalProgressRequestPayload: Encodable {
    let origin: GoalProgressSuggestionSource
    let sources: [GoalProgressSourceDocument]
    let goals: [GoalProgressGoalContext]
}

extension GoalProgressSuggestionSource {
    var sourceID: UUID {
        switch self {
        case let .journal(id), let .processedSession(id): id
        }
    }

    var journalID: UUID? {
        guard case let .journal(id) = self else { return nil }
        return id
    }
}

private extension TranscriptSegment.Speaker {
    var goalProgressTitle: String {
        switch self {
        case .patient: "Patient"
        case .provider: "Provider"
        case .unknown: "Unknown speaker"
        }
    }
}
