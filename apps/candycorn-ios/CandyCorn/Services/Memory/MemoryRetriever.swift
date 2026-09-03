import Foundation

struct MemoryRetriever: MemoryRetrieving, Sendable {
    private static let maximumSnapshotRecords = 100_000
    private static let searchLimit = 100
    private static let moodTrendID = UUID(uuidString: "ffffffff-ffff-4fff-8fff-fffffffffff5")!

    private let careStore: any CareStore
    private let builder: ContextPacketBuilder

    init(careStore: any CareStore, limits: ContextPacketLimits = .appointment) {
        self.careStore = careStore
        builder = ContextPacketBuilder(limits: limits)
    }

    func retrieve(_ request: MemoryRetrievalRequest) async throws -> ContextPacket {
        guard request.window.start <= request.window.end,
              request.window.start.timeIntervalSinceReferenceDate.isFinite,
              request.window.end.timeIntervalSinceReferenceDate.isFinite,
              request.now.timeIntervalSinceReferenceDate.isFinite else {
            throw VaultRepositoryError.invalidInput
        }
        let snapshot = try await careStore.snapshot()
        try validate(snapshot)
        let session = latestSession(in: snapshot, request: request)
        let boundary = max(request.window.start, session?.occurredAt ?? request.window.start)
        let goals = includedGoals(in: snapshot)
        let talkingPoints = includedTalkingPoints(in: snapshot, kind: request.appointmentKind)
        let queries = relevanceQueries(goals: goals, talkingPoints: talkingPoints)
        let searchScores = await scores(for: queries)
        var omitted = 0
        var candidates: [ContextPacketItem] = []

        if let session {
            candidates += summaryItems(for: session)
            let evidence = transcriptItems(for: session, transcript: snapshot.transcript)
            candidates += evidence.items
            omitted += evidence.omitted
        }
        candidates += goalItems(goals)
        candidates += progressItems(snapshot.goalProgress, goals: goals, boundary: boundary, end: request.window.end)
        candidates += talkingPointItems(talkingPoints)

        let journals = journalItems(
            snapshot.journals,
            boundary: boundary,
            end: request.window.end,
            queries: queries,
            searchScores: searchScores
        )
        candidates += journals.items
        omitted += journals.omitted
        candidates += moodItems(snapshot.moods, boundary: boundary, end: request.window.end)
        return try builder.build(request: request, candidates: candidates, alreadyOmitted: omitted)
    }

    private func validate(_ snapshot: CareSnapshot) throws {
        let counts = [
            snapshot.journals.count, snapshot.moods.count, snapshot.appointments.count,
            snapshot.goals.count, snapshot.goalProgress.count, snapshot.talkingPoints.count,
            snapshot.artifacts.count, snapshot.attachments.count, snapshot.providers.count,
            snapshot.transcript.count, snapshot.sessionProcessing.count,
            snapshot.speakerAssignments.count, snapshot.speakerEmbeddings.count,
            snapshot.patientVoiceProfiles.count, snapshot.debriefDecisions.count,
        ]
        guard counts.count == 15,
              counts.allSatisfy({ $0 <= Self.maximumSnapshotRecords }) else {
            throw VaultRepositoryError.invalidInput
        }
    }

    private func latestSession(in snapshot: CareSnapshot, request: MemoryRetrievalRequest) -> ResolvedSession? {
        var processing: [UUID: SessionProcessingRecord] = [:]
        for record in snapshot.sessionProcessing where processing[record.appointmentID] == nil {
            processing[record.appointmentID] = record
        }
        var artifacts: [UUID: AIArtifact] = [:]
        for artifact in snapshot.artifacts where artifacts[artifact.id] == nil {
            artifacts[artifact.id] = artifact
        }
        let candidates = snapshot.appointments.compactMap { appointment -> ResolvedSession? in
            guard appointment.kind == request.appointmentKind, appointment.status == .completed,
                  let occurredAt = appointment.endedAt ?? appointment.startedAt ?? appointment.scheduledAt,
                  occurredAt <= request.window.end, let summaryID = appointment.summaryID,
                  let artifact = artifacts[summaryID], artifact.kind == .sessionSummary else { return nil }
            let record = processing[appointment.id]
            if let record, record.stage != .ready { return nil }
            guard let summary = try? PersistenceCoding.decode(
                StructuredSessionSummaryResult.self,
                from: artifact.structuredPayload,
                table: "ai_artifacts",
                id: artifact.id.uuidString.lowercased()
            ), summary.template == Self.template(for: appointment.kind) else { return nil }
            return ResolvedSession(
                appointment: appointment,
                artifact: artifact,
                summary: summary,
                occurredAt: occurredAt,
                hasReadyProcessingRecord: record?.stage == .ready
            )
        }
        return candidates.sorted {
            if $0.hasReadyProcessingRecord != $1.hasReadyProcessingRecord {
                return $0.hasReadyProcessingRecord
            }
            if $0.occurredAt != $1.occurredAt { return $0.occurredAt > $1.occurredAt }
            return Self.uuid($0.appointment.id) < Self.uuid($1.appointment.id)
        }.first
    }

    private func summaryItems(for session: ResolvedSession) -> [ContextPacketItem] {
        var titled: [(String, StructuredSessionSummaryItem)] = session.summary.debriefTopics.map {
            ("What you talked about", $0)
        }
        let sectionOrder = Dictionary(uniqueKeysWithValues: SessionSummarySectionKind.allCases.enumerated().map { ($0.element, $0.offset) })
        let sections = session.summary.sections.sorted {
            let left = sectionOrder[$0.kind] ?? Int.max
            let right = sectionOrder[$1.kind] ?? Int.max
            if left != right { return left < right }
            return Self.uuid($0.id) < Self.uuid($1.id)
        }
        for section in sections {
            titled += section.items.map { (section.title, $0) }
        }
        titled += session.summary.discussedTalkingPoints.map { ("Discussed talking point", $0) }
        return titled.map { title, item in
            ContextPacketItem(
                id: item.id,
                sourceIDs: Self.unique([session.artifact.id] + item.evidence.map(\.sourceID)),
                kind: .sessionSummary,
                title: title,
                text: item.text,
                occurredAt: session.occurredAt,
                provenance: Self.voice(item.provenance),
                evidence: item.evidence,
                relevanceRank: nil
            )
        }
    }

    private func transcriptItems(
        for session: ResolvedSession,
        transcript: [TranscriptSegment]
    ) -> (items: [ContextPacketItem], omitted: Int) {
        let summaryItems = session.summary.debriefTopics
            + session.summary.sections.flatMap(\.items)
            + session.summary.discussedTalkingPoints
        var cited: [UUID: Bool] = [:]
        for item in summaryItems {
            for citation in item.evidence {
                cited[citation.sourceID, default: false] = cited[citation.sourceID, default: false]
                    || item.provenance == .candyCorn
            }
        }
        let segments = transcript.filter {
            $0.appointmentID == session.appointment.id && cited[$0.id] != nil
        }.sorted {
            if $0.startMilliseconds != $1.startMilliseconds { return $0.startMilliseconds < $1.startMilliseconds }
            return Self.uuid($0.id) < Self.uuid($1.id)
        }
        var omitted = max(0, cited.count - segments.count)
        let items = segments.compactMap { segment -> ContextPacketItem? in
            let provenance: ProvenanceVoice
            switch segment.speaker {
            case .patient: provenance = .user
            case .provider: provenance = .provider
            case .unknown:
                guard cited[segment.id] == true else {
                    omitted += 1
                    return nil
                }
                provenance = .candyCorn
            }
            return ContextPacketItem(
                id: segment.id,
                sourceIDs: [segment.id, session.appointment.id],
                kind: .transcriptEvidence,
                title: "Transcript at \(Self.clock(segment.startMilliseconds))",
                text: segment.text,
                occurredAt: session.occurredAt,
                provenance: provenance,
                evidence: [EvidenceCitation(
                    sourceID: segment.id,
                    quote: segment.text,
                    timestampMilliseconds: segment.startMilliseconds
                )],
                relevanceRank: nil
            )
        }
        return (items, omitted)
    }

    private func includedGoals(in snapshot: CareSnapshot) -> [Goal] {
        snapshot.goals.filter {
            ($0.cadence == .homework && $0.status != .completed && $0.status != .dismissed)
                || ($0.cadence != .homework && $0.status == .active)
        }.sorted {
            if ($0.cadence == .homework) != ($1.cadence == .homework) { return $0.cadence == .homework }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return Self.uuid($0.id) < Self.uuid($1.id)
        }
    }

    private func goalItems(_ goals: [Goal]) -> [ContextPacketItem] {
        goals.map { goal in
            let detail = Self.nonBlank(goal.detail) ?? "Cadence: \(goal.cadence.rawValue)."
            return ContextPacketItem(
                id: goal.id,
                sourceIDs: Self.unique([goal.id] + [goal.sourceEntityID].compactMap { $0 }),
                kind: goal.cadence == .homework ? .homework : .activeGoal,
                title: goal.title,
                text: detail,
                occurredAt: goal.createdAt,
                provenance: goal.provenance.voice,
                evidence: [],
                relevanceRank: nil
            )
        }
    }

    private func progressItems(
        _ progress: [GoalProgress],
        goals: [Goal],
        boundary: Date,
        end: Date
    ) -> [ContextPacketItem] {
        let goalIDs = Set(goals.map(\.id))
        let titles = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, $0.title) })
        return progress.filter {
            goalIDs.contains($0.goalID) && $0.createdAt >= boundary && $0.createdAt <= end
        }.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return Self.uuid($0.id) < Self.uuid($1.id)
        }.map { value in
            ContextPacketItem(
                id: value.id,
                sourceIDs: Self.unique([value.id, value.goalID] + [value.sourceEntryID].compactMap { $0 }),
                kind: .goalProgress,
                title: "Progress on \(titles[value.goalID] ?? "goal")",
                text: value.note,
                occurredAt: value.createdAt,
                provenance: value.source == .aiSuggestedProgress ? .candyCorn : .user,
                evidence: [],
                relevanceRank: nil
            )
        }
    }

    private func includedTalkingPoints(in snapshot: CareSnapshot, kind: Appointment.Kind) -> [TalkingPoint] {
        snapshot.talkingPoints.filter {
            $0.status == .open && ($0.targetAppointmentKind == nil || $0.targetAppointmentKind == kind)
        }.sorted {
            if $0.isImportant != $1.isImportant { return $0.isImportant }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return Self.uuid($0.id) < Self.uuid($1.id)
        }
    }

    private func talkingPointItems(_ points: [TalkingPoint]) -> [ContextPacketItem] {
        points.map { point in
            ContextPacketItem(
                id: point.id,
                sourceIDs: Self.unique([point.id] + [point.sourceID].compactMap { $0 }),
                kind: .talkingPoint,
                title: point.isImportant ? "Important talking point" : "Talking point",
                text: point.text,
                occurredAt: point.createdAt,
                provenance: point.provenance.voice,
                evidence: [],
                relevanceRank: nil
            )
        }
    }

    private func journalItems(
        _ journals: [JournalEntry],
        boundary: Date,
        end: Date,
        queries: [String],
        searchScores: [UUID: RelevanceScore]?
    ) -> (items: [ContextPacketItem], omitted: Int) {
        var omitted = 0
        let ranked = journals.compactMap { journal -> RankedJournal? in
            guard journal.createdAt > boundary, journal.createdAt <= end else { return nil }
            guard let text = Self.nonBlank(journal.cleanedText) ?? Self.nonBlank(journal.rawText) else {
                omitted += 1
                return nil
            }
            let score = searchScores?[journal.id] ?? Self.overlapScore(text: "\(journal.title) \(text)", queries: queries)
            return RankedJournal(journal: journal, text: text, score: score)
        }.sorted { Self.ranksBefore($0, $1) }
        let items = ranked.enumerated().map { index, value in
            ContextPacketItem(
                id: value.journal.id,
                sourceIDs: [value.journal.id],
                kind: .journal,
                title: value.journal.title,
                text: value.text,
                occurredAt: value.journal.createdAt,
                provenance: value.journal.provenance.voice,
                evidence: [],
                relevanceRank: index + 1
            )
        }
        return (items, omitted)
    }

    private func moodItems(_ moods: [MoodLog], boundary: Date, end: Date) -> [ContextPacketItem] {
        let included = moods.filter { $0.createdAt > boundary && $0.createdAt <= end }.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return Self.uuid($0.id) < Self.uuid($1.id)
        }
        guard !included.isEmpty else { return [] }
        let trend = ContextPacketItem(
            id: Self.moodTrendID,
            sourceIDs: included.map(\.id),
            kind: .moodTrend,
            title: "Recorded mood trend",
            text: Self.moodTrend(included),
            occurredAt: included.last?.createdAt,
            provenance: .candyCorn,
            evidence: [],
            relevanceRank: nil
        )
        let logs = included.reversed().map { mood in
            ContextPacketItem(
                id: mood.id,
                sourceIDs: [mood.id],
                kind: .moodLog,
                title: "Mood check-in",
                text: Self.moodDescription(mood),
                occurredAt: mood.createdAt,
                provenance: .user,
                evidence: [],
                relevanceRank: nil
            )
        }
        return [trend] + logs
    }

    private func relevanceQueries(goals: [Goal], talkingPoints: [TalkingPoint]) -> [String] {
        var values: [String] = []
        let orderedGoals = goals.filter { $0.status == .active }.sorted { Self.uuid($0.id) < Self.uuid($1.id) }
        for goal in orderedGoals {
            values.append(goal.title)
            if let detail = Self.nonBlank(goal.detail) { values.append(detail) }
        }
        for point in talkingPoints.sorted(by: { Self.uuid($0.id) < Self.uuid($1.id) }) {
            values.append(point.text)
        }
        var seen: Set<String> = []
        return values.compactMap { value in
            let normalized = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
            let key = normalized.lowercased()
            guard !normalized.isEmpty, seen.insert(key).inserted else { return nil }
            return normalized
        }.prefix(builder.limits.maximumSearchQueries).map { $0 }
    }

    private func scores(for queries: [String]) async -> [UUID: RelevanceScore]? {
        guard !queries.isEmpty else { return [:] }
        var scores: [UUID: RelevanceScore] = [:]
        for query in queries {
            let hits: [SearchHit]
            do {
                hits = try await careStore.search(query, limit: Self.searchLimit)
            } catch {
                return nil
            }
            var seen: Set<UUID> = []
            for (position, hit) in hits.prefix(Self.searchLimit).enumerated() where seen.insert(hit.entityID).inserted {
                var score = scores[hit.entityID] ?? RelevanceScore(matches: 0, bestPosition: Int.max)
                score.matches += 1
                score.bestPosition = min(score.bestPosition, position)
                scores[hit.entityID] = score
            }
        }
        return scores
    }

    private static func ranksBefore(_ lhs: RankedJournal, _ rhs: RankedJournal) -> Bool {
        if lhs.score.matches != rhs.score.matches { return lhs.score.matches > rhs.score.matches }
        if lhs.score.bestPosition != rhs.score.bestPosition { return lhs.score.bestPosition < rhs.score.bestPosition }
        if lhs.journal.createdAt != rhs.journal.createdAt { return lhs.journal.createdAt > rhs.journal.createdAt }
        return uuid(lhs.journal.id) < uuid(rhs.journal.id)
    }

    private static func overlapScore(text: String, queries: [String]) -> RelevanceScore {
        let textTokens = tokens(text)
        var matches = 0
        for query in queries where !textTokens.isDisjoint(with: tokens(query)) {
            matches += 1
        }
        return RelevanceScore(matches: matches, bestPosition: Int.max)
    }

    private static func tokens(_ value: String) -> Set<String> {
        let pieces = value.unicodeScalars.split { !CharacterSet.alphanumerics.contains($0) }
        return Set(pieces.prefix(500).map { String($0).lowercased() }.filter { $0.count > 1 })
    }

    private static func moodTrend(_ moods: [MoodLog]) -> String {
        guard moods.count > 1 else { return "One check-in was recorded: \(moodDescription(moods[0]))" }
        var parts: [String] = []
        appendTrend("mood", values: moods.compactMap(\.mood), to: &parts)
        appendTrend("anxiety", values: moods.compactMap(\.anxiety), to: &parts)
        appendTrend("energy", values: moods.compactMap(\.energy), to: &parts)
        let prefix = "Across \(moods.count) check-ins"
        guard !parts.isEmpty else { return "\(prefix), no numeric mood dimensions were recorded." }
        return "\(prefix), \(parts.joined(separator: "; ")). These recorded values do not establish a cause."
    }

    private static func appendTrend(_ name: String, values: [Int], to parts: inout [String]) {
        guard let first = values.first, let last = values.last else { return }
        if values.count == 1 {
            parts.append("\(name) had one value of \(first)")
        } else if first == last {
            parts.append("\(name) began and ended at \(first)")
        } else {
            parts.append("\(name) changed from \(first) to \(last)")
        }
    }

    private static func moodDescription(_ mood: MoodLog) -> String {
        var parts: [String] = []
        if let value = mood.mood { parts.append("mood \(value)") }
        if let value = mood.anxiety { parts.append("anxiety \(value)") }
        if let value = mood.energy { parts.append("energy \(value)") }
        for key in mood.customValues.keys.sorted() {
            if let value = mood.customValues[key] { parts.append("\(key) \(value)") }
        }
        if let note = nonBlank(mood.note) { parts.append("note: \(note)") }
        return parts.isEmpty ? "A check-in was recorded without numeric dimensions or a note." : parts.joined(separator: ", ") + "."
    }

    private static func voice(_ provenance: SessionSummaryItemProvenance) -> ProvenanceVoice {
        switch provenance {
        case .patient: .user
        case .provider: .provider
        case .candyCorn: .candyCorn
        }
    }

    private static func template(for kind: Appointment.Kind) -> SessionSummaryTemplate {
        kind == .tms ? .tms : .therapy
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func unique(_ values: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return values.filter { seen.insert($0).inserted }
    }

    private static func uuid(_ value: UUID) -> String { value.uuidString.lowercased() }

    private static func clock(_ milliseconds: Int) -> String {
        let seconds = max(0, milliseconds / 1_000)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct ResolvedSession: Sendable {
    let appointment: Appointment
    let artifact: AIArtifact
    let summary: StructuredSessionSummaryResult
    let occurredAt: Date
    let hasReadyProcessingRecord: Bool
}

private struct RelevanceScore: Sendable {
    var matches: Int
    var bestPosition: Int
}

private struct RankedJournal: Sendable {
    let journal: JournalEntry
    let text: String
    let score: RelevanceScore
}
