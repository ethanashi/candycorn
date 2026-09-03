import Foundation

/// Screenshot-mode only: gives History a weekly summary and Goals a progress suggestion so the
/// Phase 5 surfaces render with content. Built through the real preparation and validator, so the
/// seeded artifact is exactly what a live run would store. Never used outside `-screen` launches.
enum Phase5ScreenshotSeed {
    private static let routes: Set<String> = ["/history", "/goals", "/today"]
    private static let weeklyID = uuid("8F500000-0000-0000-0000-000000000001")
    private static let progressID = uuid("8F500000-0000-0000-0000-000000000002")
    private static let suggestionID = uuid("8F500000-0000-0000-0000-000000000003")
    private static let provider = "openrouter"
    private static let model = "deepseek/deepseek-v4-flash-0731"

    static func applyingIfNeeded(to source: CareSnapshot, arguments: [String], now: Date) -> CareSnapshot {
        guard let flag = arguments.firstIndex(of: "-screen") else { return source }
        let valueIndex = arguments.index(after: flag)
        guard valueIndex < arguments.endIndex, routes.contains(arguments[valueIndex]) else { return source }
        var snapshot = source
        seedWeeklySummary(into: &snapshot, now: now)
        seedProgressSuggestion(into: &snapshot, now: now)
        return snapshot
    }

    private static func seedWeeklySummary(into snapshot: inout CareSnapshot, now: Date) {
        guard let preparation = try? WeeklyConsolidator.makePreparation(
            snapshot: snapshot, for: now, calendar: .autoupdatingCurrent
        ) else { return }
        let input = preparation.input
        let userSources = input.sources.filter { $0.provenance == .user }
        func item(from source: WeeklySummarySource?) -> [WeeklySummaryItem] {
            guard let source else { return [] }
            let sentence = firstSentence(of: source.document.text)
            guard !sentence.isEmpty else { return [] }
            return [WeeklySummaryItem(
                id: UUID(), text: sentence, provenance: .user,
                evidence: [EvidenceCitation(sourceID: source.id, quote: sentence, timestampMilliseconds: nil)]
            )]
        }
        let mood = userSources.first { $0.document.kind == .moodTrend }
        let work = userSources.first { $0.document.kind == .homework || $0.document.kind == .goal }
        let journal = userSources.first { $0.document.kind == .journal }
        let point = userSources.first { $0.document.kind == .talkingPoint }
        let sections = [
            WeeklySummarySection(id: UUID(), kind: .moodTrend, items: item(from: mood)),
            WeeklySummarySection(id: UUID(), kind: .completedWork, items: item(from: work)),
            WeeklySummarySection(id: UUID(), kind: .recurringTopics, items: item(from: journal)),
            WeeklySummarySection(id: UUID(), kind: .openForNextAppointment, items: item(from: point)),
        ]
        let result = WeeklySummaryResult(
            interval: input.interval,
            sections: sections,
            metadata: AIResultMetadata(provider: provider, model: model, usage: AIUsage())
        )
        guard (try? OrganizerOutputValidator().validatedWeeklySummary(result, input: input)) != nil else { return }
        let payload = WeeklySummaryArtifactPayload(
            inputInterval: input.interval, sources: input.sources,
            requestText: input.requestText, result: result
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload) else { return }
        let cited = Set(result.sections.flatMap(\.items).flatMap(\.evidence).map(\.sourceID))
        upsert(AIArtifact(
            id: weeklyID, kind: .weeklySummary, sourceIDs: input.sources.map(\.id).filter { cited.contains($0) },
            provider: provider, model: model, structuredPayload: data, createdAt: now
        ), in: &snapshot.artifacts)
    }

    private static func seedProgressSuggestion(into snapshot: inout CareSnapshot, now: Date) {
        let goalID = uuid("40000000-0000-0000-0000-000000000004")
        guard snapshot.goals.contains(where: { $0.id == goalID && $0.status == .active }),
              let journal = snapshot.journals.first(where: { $0.id == SeededData.footballJournalID }) else { return }
        let quote = "I got angry, went to the gym, and felt better"
        guard journal.rawText.contains(quote) else { return }
        let suggestion = GoalProgressSuggestion(
            id: suggestionID, goalID: goalID, mark: .doneToday,
            note: "Your Sep 5 journal says you used exercise when the football thoughts came back.",
            evidence: [EvidenceCitation(sourceID: journal.id, quote: quote, timestampMilliseconds: nil)],
            resolution: .pending
        )
        let document = SourceTextDocument(
            id: journal.id, kind: .journal, title: journal.title, text: journal.rawText, occurredAt: journal.createdAt
        )
        let payload = GoalProgressSuggestionArtifactPayload(
            origin: .journal(journal.id),
            input: GoalProgressSuggestionInput(
                originID: journal.id, origin: .journal(journal.id),
                sources: [GoalProgressSourceDocument(document: document, startMilliseconds: nil, endMilliseconds: nil)],
                goals: snapshot.goals.filter { $0.status == .active }.map {
                    GoalProgressGoalContext(id: $0.id, title: $0.title, detail: $0.detail, cadence: $0.cadence)
                },
                requestText: "Screenshot seed"
            ),
            result: GoalProgressSuggestionResult(
                suggestions: [suggestion],
                metadata: AIResultMetadata(provider: provider, model: model, usage: AIUsage())
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload) else { return }
        upsert(AIArtifact(
            id: progressID, kind: .goalProgressSuggestions, sourceIDs: [journal.id, goalID],
            provider: provider, model: model, structuredPayload: data, createdAt: now
        ), in: &snapshot.artifacts)
    }

    private static func firstSentence(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let end = trimmed.firstIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) else {
            return String(trimmed.prefix(160))
        }
        return String(trimmed[..<end])
    }

    private static func upsert(_ artifact: AIArtifact, in artifacts: inout [AIArtifact]) {
        artifacts.removeAll { $0.id == artifact.id }
        artifacts.append(artifact)
    }

    private static func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}
