import Foundation

struct WeeklySummaryPreparation: Equatable, Sendable {
    let input: WeeklySummaryInput
    let omittedSourceCount: Int
}

struct WeeklySummaryWorkProduct: Equatable, Sendable {
    let artifact: AIArtifact
    let result: WeeklySummaryResult
}

actor WeeklyConsolidator {
    static let maximumSources = 48
    static let maximumSourceCharacters = 1_500
    static let maximumRequestCharacters = 16_000
    private static let maximumCandidates = 700_000

    private let careStore: any CareStore
    private let languageModel: any CandyCornLanguageModel
    private let calendar: Calendar
    private let validator: OrganizerOutputValidator
    private let now: @Sendable () -> Date

    init(
        careStore: any CareStore,
        languageModel: any CandyCornLanguageModel,
        calendar: Calendar = .autoupdatingCurrent,
        validator: OrganizerOutputValidator = OrganizerOutputValidator(),
        now: @escaping @Sendable () -> Date
    ) {
        self.careStore = careStore
        self.languageModel = languageModel
        self.calendar = calendar
        self.validator = validator
        self.now = now
    }

    func prepareSummary(for date: Date) async throws -> WeeklySummaryPreparation? {
        let snapshot = try await careStore.snapshot()
        return try Self.makePreparation(snapshot: snapshot, for: date, calendar: calendar)
    }

    func generate(_ input: WeeklySummaryInput) async throws -> WeeklySummaryWorkProduct {
        try validator.validateWeeklySummaryInput(input)
        guard input.requestText == (try Self.canonicalRequestText(interval: input.interval, sources: input.sources)),
              input.interval == (try Self.weekInterval(containing: now(), calendar: calendar)) else {
            throw AIProviderError.invalidInput
        }
        let before = try await careStore.snapshot()
        guard try Self.makePreparation(snapshot: before, for: input.interval.start, calendar: calendar)?.input == input else {
            throw AIProviderError.invalidInput
        }
        if let existing = try existingProduct(for: input, artifacts: before.artifacts) { return existing }

        let proposed = try await languageModel.consolidateWeek(input)
        let result = try validator.validatedWeeklySummary(proposed, input: input)
        try Task.checkCancellation()
        let after = try await careStore.snapshot()
        guard try Self.makePreparation(snapshot: after, for: input.interval.start, calendar: calendar)?.input == input else {
            throw AIProviderError.invalidInput
        }
        let artifact = try Self.makeArtifact(input: input, result: result, createdAt: now())
        return WeeklySummaryWorkProduct(artifact: artifact, result: result)
    }

    static func weekInterval(containing date: Date, calendar: Calendar) throws -> DateInterval {
        guard date.timeIntervalSinceReferenceDate.isFinite,
              let interval = calendar.dateInterval(of: .weekOfYear, for: date),
              interval.start < interval.end,
              interval.contains(date) else {
            throw AIProviderError.invalidInput
        }
        return interval
    }

    static func makePreparation(
        snapshot: CareSnapshot,
        for date: Date,
        calendar: Calendar
    ) throws -> WeeklySummaryPreparation? {
        try validateSnapshotBounds(snapshot)
        let interval = try weekInterval(containing: date, calendar: calendar)
        let candidates = sourceCandidates(snapshot: snapshot, interval: interval).sorted(by: sourceOrder)
        var selected: [WeeklySummarySource] = []
        var omitted = 0
        for candidate in candidates.prefix(maximumCandidates) {
            guard selected.count < maximumSources,
                  !selected.contains(where: { $0.id == candidate.source.id }) else {
                omitted += 1
                continue
            }
            guard let source = fitting(candidate.source, interval: interval, selected: selected) else {
                omitted += 1
                continue
            }
            selected.append(source)
        }
        guard !selected.isEmpty else { return nil }
        let text = try canonicalRequestText(interval: interval, sources: selected)
        guard text.count <= maximumRequestCharacters else { throw AIProviderError.invalidInput }
        return WeeklySummaryPreparation(
            input: WeeklySummaryInput(interval: interval, sources: selected, requestText: text),
            omittedSourceCount: omitted
        )
    }

    static func canonicalRequestText(
        interval: DateInterval,
        sources: [WeeklySummarySource]
    ) throws -> String {
        let payload = WeeklySummaryRequestPayload(
            intervalStart: interval.start,
            intervalEnd: interval.end,
            sources: sources
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8),
              text.count <= maximumRequestCharacters else {
            throw AIProviderError.invalidInput
        }
        return text
    }

    static func currentSummary(
        in artifacts: [AIArtifact],
        for date: Date,
        calendar: Calendar = .autoupdatingCurrent,
        validator: OrganizerOutputValidator = OrganizerOutputValidator()
    ) -> WeeklySummaryResult? {
        guard artifacts.count <= 100_000,
              let interval = try? weekInterval(containing: date, calendar: calendar) else { return nil }
        let ordered = artifacts.filter { $0.kind == .weeklySummary }.sorted {
            ($0.createdAt, $0.id.uuidString.lowercased()) > ($1.createdAt, $1.id.uuidString.lowercased())
        }
        for artifact in ordered.prefix(1_024) {
            guard let product = try? decodedProduct(artifact, validator: validator),
                  product.input.interval == interval,
                  product.result.interval == interval else { continue }
            return product.result
        }
        return nil
    }

    private func existingProduct(
        for input: WeeklySummaryInput,
        artifacts: [AIArtifact]
    ) throws -> WeeklySummaryWorkProduct? {
        guard artifacts.count <= 100_000 else { throw AIProviderError.invalidInput }
        let ordered = artifacts.filter { $0.kind == .weeklySummary }.sorted {
            ($0.createdAt, $0.id.uuidString.lowercased()) > ($1.createdAt, $1.id.uuidString.lowercased())
        }
        for artifact in ordered.prefix(1_024) {
            guard let product = try? Self.decodedProduct(artifact, validator: validator),
                  product.input == input else { continue }
            return WeeklySummaryWorkProduct(artifact: artifact, result: product.result)
        }
        return nil
    }

    private static func makeArtifact(
        input: WeeklySummaryInput,
        result: WeeklySummaryResult,
        createdAt: Date
    ) throws -> AIArtifact {
        let provider = result.metadata.provider.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = result.metadata.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceIDs = citedSourceIDs(result: result, sources: input.sources)
        guard !provider.isEmpty, !model.isEmpty, !sourceIDs.isEmpty else {
            throw AIProviderError.invalidResponse
        }
        let payload = WeeklySummaryArtifactPayload(
            inputInterval: input.interval,
            sources: input.sources,
            requestText: input.requestText,
            result: result
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        guard !data.isEmpty else { throw AIProviderError.invalidResponse }
        return AIArtifact(
            id: UUID(), kind: .weeklySummary, sourceIDs: sourceIDs,
            provider: provider, model: model, structuredPayload: data, createdAt: createdAt
        )
    }

    private static func decodedProduct(
        _ artifact: AIArtifact,
        validator: OrganizerOutputValidator
    ) throws -> (input: WeeklySummaryInput, result: WeeklySummaryResult) {
        let payload = try JSONDecoder().decode(WeeklySummaryArtifactPayload.self, from: artifact.structuredPayload)
        let input = WeeklySummaryInput(
            interval: payload.inputInterval,
            sources: payload.sources,
            requestText: payload.requestText
        )
        try validator.validateWeeklySummaryInput(input)
        guard input.requestText == (try canonicalRequestText(interval: input.interval, sources: input.sources)),
              artifact.provider == payload.result.metadata.provider,
              artifact.model == payload.result.metadata.model else {
            throw AIProviderError.invalidResponse
        }
        let result = try validator.validatedWeeklySummary(payload.result, input: input)
        guard artifact.sourceIDs == citedSourceIDs(result: result, sources: input.sources) else {
            throw AIProviderError.invalidResponse
        }
        return (input, result)
    }

    private static func citedSourceIDs(
        result: WeeklySummaryResult,
        sources: [WeeklySummarySource]
    ) -> [UUID] {
        let cited = Set(result.sections.flatMap(\.items).flatMap(\.evidence).map(\.sourceID))
        return sources.map(\.id).filter { cited.contains($0) }
    }
}

private extension WeeklyConsolidator {
    enum SourceCategory: Int, Sendable {
        case journal, mood, goalProgress, appointment, sessionSummary, talkingPoint, activeGoal
    }

    struct SourceCandidate: Sendable {
        let category: SourceCategory
        let source: WeeklySummarySource
    }

    static func validateSnapshotBounds(_ snapshot: CareSnapshot) throws {
        guard snapshot.journals.count <= 100_000, snapshot.moods.count <= 100_000,
              snapshot.goals.count <= 100_000, snapshot.goalProgress.count <= 100_000,
              snapshot.appointments.count <= 100_000, snapshot.talkingPoints.count <= 100_000,
              snapshot.artifacts.count <= 100_000,
              Set(snapshot.goals.map(\.id)).count == snapshot.goals.count,
              Set(snapshot.artifacts.map(\.id)).count == snapshot.artifacts.count else {
            throw AIProviderError.invalidInput
        }
    }

    static func sourceCandidates(snapshot: CareSnapshot, interval: DateInterval) -> [SourceCandidate] {
        let goals = Dictionary(uniqueKeysWithValues: snapshot.goals.map { ($0.id, $0) })
        var values: [SourceCandidate] = []
        values.reserveCapacity(min(700_000, snapshot.journals.count + snapshot.moods.count + snapshot.goalProgress.count))
        appendJournals(snapshot.journals, interval: interval, to: &values)
        appendMoods(snapshot.moods, interval: interval, to: &values)
        appendProgress(snapshot.goalProgress, goals: goals, interval: interval, to: &values)
        appendAppointments(snapshot: snapshot, interval: interval, to: &values)
        let progressedGoalIDs = Set(snapshot.goalProgress.lazy.filter {
            contains($0.createdAt, in: interval)
        }.map(\.goalID))
        appendOpenItems(snapshot: snapshot, interval: interval, progressedGoalIDs: progressedGoalIDs, to: &values)
        return values
    }

    static func appendJournals(
        _ journals: [JournalEntry],
        interval: DateInterval,
        to values: inout [SourceCandidate]
    ) {
        for journal in journals.prefix(100_000) where contains(journal.createdAt, in: interval) {
            guard values.count < maximumCandidates else { return }
            let cleaned = journal.cleanedText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let raw = journal.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = cleaned.flatMap { $0.isEmpty ? nil : $0 } ?? raw
            guard !text.isEmpty else { continue }
            values.append(candidate(
                category: .journal, id: journal.id, kind: .journal, title: journal.title,
                text: text, occurredAt: journal.createdAt, provenance: journal.provenance.voice
            ))
        }
    }

    static func appendMoods(
        _ moods: [MoodLog],
        interval: DateInterval,
        to values: inout [SourceCandidate]
    ) {
        for mood in moods.prefix(100_000) where contains(mood.createdAt, in: interval) {
            guard values.count < maximumCandidates else { return }
            var parts: [String] = []
            if let value = mood.mood { parts.append("Mood \(value)/10") }
            if let value = mood.anxiety { parts.append("Anxiety \(value)/10") }
            if let value = mood.energy { parts.append("Energy \(value)/10") }
            for key in mood.customValues.keys.sorted().prefix(64) {
                if let value = mood.customValues[key] { parts.append("\(key) \(value)/10") }
            }
            if let note = mood.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                parts.append("Note: \(note)")
            }
            if parts.isEmpty { parts.append("A mood check-in was recorded.") }
            values.append(candidate(
                category: .mood, id: mood.id, kind: .moodTrend, title: "Mood check-in",
                text: parts.joined(separator: ", "), occurredAt: mood.createdAt, provenance: .user
            ))
        }
    }

    static func appendProgress(
        _ progressValues: [GoalProgress],
        goals: [UUID: Goal],
        interval: DateInterval,
        to values: inout [SourceCandidate]
    ) {
        for progress in progressValues.prefix(100_000) where contains(progress.createdAt, in: interval) {
            guard values.count < maximumCandidates else { return }
            guard let goal = goals[progress.goalID] else { continue }
            var lines = ["Goal: \(goal.title)"]
            if let detail = goal.detail, !detail.isEmpty { lines.append("Goal detail: \(detail)") }
            if let mark = progress.mark { lines.append("Progress mark: \(mark.rawValue)") }
            if !progress.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("Progress note: \(progress.note)")
            }
            let voice: ProvenanceVoice = progress.source == .userConfirmed ? .user : .candyCorn
            values.append(candidate(
                category: .goalProgress, id: progress.id, kind: .goal,
                title: "Progress on \(goal.title)", text: lines.joined(separator: "\n"),
                occurredAt: progress.createdAt, provenance: voice
            ))
        }
    }

    static func appendAppointments(
        snapshot: CareSnapshot,
        interval: DateInterval,
        to values: inout [SourceCandidate]
    ) {
        let artifacts = Dictionary(uniqueKeysWithValues: snapshot.artifacts.map { ($0.id, $0) })
        for appointment in snapshot.appointments.prefix(100_000) {
            guard values.count < maximumCandidates else { return }
            let occurredAt = appointment.endedAt ?? appointment.startedAt ?? appointment.scheduledAt
            guard appointment.status == .completed, let occurredAt, contains(occurredAt, in: interval) else { continue }
            values.append(candidate(
                category: .appointment, id: appointment.id, kind: .sessionNotes,
                title: "Completed \(appointment.kind.displayName.lowercased()) appointment",
                text: "A \(appointment.kind.rawValue) appointment was recorded as completed.",
                occurredAt: occurredAt, provenance: .candyCorn
            ))
            guard let summaryID = appointment.summaryID,
                  let artifact = artifacts[summaryID], artifact.kind == .sessionSummary,
                  let result = try? JSONDecoder().decode(StructuredSessionSummaryResult.self, from: artifact.structuredPayload) else {
                continue
            }
            let items = result.debriefTopics + result.sections.flatMap(\.items) + result.discussedTalkingPoints
            for item in items.prefix(1_024) {
                guard values.count < maximumCandidates else { return }
                values.append(candidate(
                    category: .sessionSummary, id: item.id, kind: .sessionNotes,
                    title: "Session summary item", text: item.text,
                    occurredAt: occurredAt, provenance: provenance(item.provenance)
                ))
            }
        }
    }

    static func appendOpenItems(
        snapshot: CareSnapshot,
        interval: DateInterval,
        progressedGoalIDs: Set<UUID>,
        to values: inout [SourceCandidate]
    ) {
        for point in snapshot.talkingPoints.prefix(100_000)
        where point.status == .open && point.createdAt < interval.end {
            guard values.count < maximumCandidates else { return }
            values.append(candidate(
                category: .talkingPoint, id: point.id, kind: .talkingPoint,
                title: point.isImportant ? "Important open talking point" : "Open talking point",
                text: point.text, occurredAt: point.createdAt, provenance: point.provenance.voice
            ))
        }
        for goal in snapshot.goals.prefix(100_000)
        where goal.status == .active && goal.createdAt < interval.end && !progressedGoalIDs.contains(goal.id) {
            guard values.count < maximumCandidates else { return }
            let text = goal.detail.map { "\(goal.title)\n\($0)" } ?? goal.title
            values.append(candidate(
                category: .activeGoal, id: goal.id, kind: .goal,
                title: "Active goal: \(goal.title)", text: text,
                occurredAt: goal.createdAt, provenance: goal.provenance.voice
            ))
        }
    }

    static func candidate(
        category: SourceCategory,
        id: UUID,
        kind: SourceTextDocument.Kind,
        title: String,
        text: String,
        occurredAt: Date,
        provenance: ProvenanceVoice
    ) -> SourceCandidate {
        SourceCandidate(category: category, source: WeeklySummarySource(
            document: SourceTextDocument(
                id: id, kind: kind, title: bounded(title, maximum: 240),
                text: bounded(text, maximum: maximumSourceCharacters), occurredAt: occurredAt
            ),
            provenance: provenance
        ))
    }

    static func fitting(
        _ source: WeeklySummarySource,
        interval: DateInterval,
        selected: [WeeklySummarySource]
    ) -> WeeklySummarySource? {
        var candidate = source
        for _ in 0..<16 {
            let prospective = selected + [candidate]
            if let text = try? canonicalRequestText(interval: interval, sources: prospective),
               text.count <= maximumRequestCharacters {
                return candidate
            }
            let length = candidate.document.text.count
            guard length > 1 else { return nil }
            candidate = replacingText(candidate, with: String(candidate.document.text.prefix(max(1, length / 2))))
        }
        return nil
    }

    static func replacingText(_ source: WeeklySummarySource, with text: String) -> WeeklySummarySource {
        WeeklySummarySource(
            document: SourceTextDocument(
                id: source.document.id, kind: source.document.kind, title: source.document.title,
                text: text, occurredAt: source.document.occurredAt
            ),
            provenance: source.provenance
        )
    }

    static func sourceOrder(_ left: SourceCandidate, _ right: SourceCandidate) -> Bool {
        if left.category != right.category { return left.category.rawValue < right.category.rawValue }
        let leftDate = left.source.document.occurredAt ?? .distantPast
        let rightDate = right.source.document.occurredAt ?? .distantPast
        if leftDate != rightDate { return leftDate > rightDate }
        return left.source.id.uuidString.lowercased() < right.source.id.uuidString.lowercased()
    }

    static func contains(_ date: Date, in interval: DateInterval) -> Bool {
        date >= interval.start && date < interval.end
    }

    static func provenance(_ value: SessionSummaryItemProvenance) -> ProvenanceVoice {
        switch value {
        case .patient: .user
        case .provider: .provider
        case .candyCorn: .candyCorn
        }
    }

    static func bounded(_ value: String, maximum: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maximum))
    }
}

private struct WeeklySummaryRequestPayload: Codable {
    let intervalStart: Date
    let intervalEnd: Date
    let sources: [WeeklySummarySource]
}
