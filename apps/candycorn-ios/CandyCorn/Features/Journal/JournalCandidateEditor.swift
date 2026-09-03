import SwiftUI

enum JournalArtifactReader {
    static func latest(
        kind: AIArtifact.Kind,
        journal: JournalEntry,
        artifacts: [AIArtifact]
    ) -> AIArtifact? {
        let photoText = artifacts
            .filter { $0.kind == .photoText && $0.sourceIDs.contains(journal.id) }
            .max { $0.createdAt < $1.createdAt }
        let sourceIDs = Set([journal.id, photoText?.id].compactMap(\.self))
        return artifacts
            .filter { $0.kind == kind && !Set($0.sourceIDs).isDisjoint(with: sourceIDs) }
            .max { $0.createdAt < $1.createdAt }
    }

    static func decode<Payload: Decodable>(
        _ type: Payload.Type,
        kind: AIArtifact.Kind,
        journal: JournalEntry,
        artifacts: [AIArtifact]
    ) -> (artifact: AIArtifact, result: Payload)? {
        guard let artifact = latest(kind: kind, journal: journal, artifacts: artifacts),
              let result = try? JSONDecoder().decode(type, from: artifact.structuredPayload) else {
            return nil
        }
        return (artifact, result)
    }
}

struct JournalSuggestionReview: Equatable, Sendable {
    let talkingPoints: [JournalSignals.TalkingPointSuggestion]
    let commitments: [JournalSignals.Commitment]

    init(signals: JournalSignals) {
        talkingPoints = Self.unique(signals.talkingPointSuggestions) { $0.id } text: { $0.text }
        commitments = Self.unique(signals.explicitCommitments) { $0.id } text: { $0.text }
    }

    private static func unique<Value>(
        _ values: [Value],
        id: (Value) -> UUID,
        text: (Value) -> String
    ) -> [Value] {
        var ids: Set<UUID> = []
        var texts: Set<String> = []
        var result: [Value] = []
        for value in values.prefix(50) {
            let normalized = text(value).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, ids.insert(id(value)).inserted, texts.insert(normalized).inserted else {
                continue
            }
            result.append(value)
        }
        return result
    }
}

struct JournalCandidateDecisions: Equatable, Sendable {
    private(set) var ignoredIDs: Set<UUID> = []
    private(set) var pendingIDs: Set<UUID> = []

    func isVisible(_ id: UUID) -> Bool { !ignoredIDs.contains(id) }
    func isPending(_ id: UUID) -> Bool { pendingIDs.contains(id) }

    mutating func begin(_ id: UUID) -> Bool {
        guard !ignoredIDs.contains(id), !pendingIDs.contains(id) else { return false }
        pendingIDs.insert(id)
        return true
    }

    mutating func finish(_ id: UUID) { pendingIDs.remove(id) }

    mutating func ignore(_ id: UUID) {
        pendingIDs.remove(id)
        ignoredIDs.insert(id)
    }
}

struct JournalCandidateDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    let journalID: UUID
    let evidence: String
    var title: String
    var cadence: Goal.Cadence

    init(candidate: JournalSignals.Commitment, journalID: UUID) {
        id = candidate.id
        self.journalID = journalID
        evidence = candidate.evidence
        title = candidate.text
        cadence = Self.supportedCadence(candidate.cadenceHint)
    }

    func makeGoal(now: Date, sourceTitle: String) -> Goal? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return Goal(
            id: id,
            title: trimmed,
            detail: nil,
            cadence: cadence,
            source: .aiSuggested,
            sourceEntityID: journalID,
            sourceTimestampMilliseconds: nil,
            status: .active,
            createdAt: now,
            targetDate: nil,
            provenance: Provenance(
                voice: .candyCorn,
                label: "Candy Corn suggested this",
                detail: "Based on \(sourceTitle). You added it.",
                occurredAt: now,
                sourceRoute: .journalSuggestions
            )
        )
    }

    static func supportedCadence(_ hint: String?) -> Goal.Cadence {
        let normalized = hint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "daily", "every day": return .daily
        case "weekly", "every week": return .weekly
        case "monthly", "every month": return .monthly
        case "ongoing": return .ongoing
        case "observation", "notice": return .observation
        case "one off", "one-off", "once": return .oneOff
        default: return .oneOff
        }
    }
}

enum JournalSuggestionFactory {
    static func talkingPoint(
        from suggestion: JournalSignals.TalkingPointSuggestion,
        journalID: UUID,
        sourceTitle: String,
        target: Appointment.Kind,
        now: Date
    ) -> TalkingPoint? {
        let text = suggestion.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return TalkingPoint(
            id: suggestion.id,
            text: text,
            source: .aiSuggestion,
            sourceID: journalID,
            targetAppointmentKind: target,
            isImportant: false,
            status: .open,
            createdAt: now,
            provenance: Provenance(
                voice: .candyCorn,
                label: "Candy Corn suggested this",
                detail: "Based on \(sourceTitle). You added it.",
                occurredAt: now,
                sourceRoute: .journalSuggestions
            )
        )
    }
}

struct JournalCandidateEditor: View {
    @State private var draft: JournalCandidateDraft
    @State private var isAdding = false
    let onCancel: () -> Void
    let onAdd: (JournalCandidateDraft) async -> Bool

    init(
        draft: JournalCandidateDraft,
        onCancel: @escaping () -> Void,
        onAdd: @escaping (JournalCandidateDraft) async -> Bool
    ) {
        _draft = State(initialValue: draft)
        self.onCancel = onCancel
        self.onAdd = onAdd
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Candidate goal") {
                    TextField("Goal", text: $draft.title, axis: .vertical)
                        .lineLimit(2...5)
                    Picker("Cadence", selection: $draft.cadence) {
                        ForEach(Self.supportedCadences, id: \.self) { cadence in
                            Text(Self.title(for: cadence)).tag(cadence)
                        }
                    }
                }
                Section("Source words") {
                    Text(draft.evidence)
                        .font(TypeScale.body)
                        .foregroundStyle(DesignTokens.cocoa)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle("Edit candidate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isAdding ? "Adding" : "Add") { add() }
                        .disabled(isAdding || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func add() {
        guard !isAdding else { return }
        isAdding = true
        Task {
            if await onAdd(draft) { onCancel() }
            isAdding = false
        }
    }

    private static let supportedCadences: [Goal.Cadence] = [
        .oneOff, .daily, .weekly, .monthly, .ongoing, .observation,
    ]

    private static func title(for cadence: Goal.Cadence) -> String {
        switch cadence {
        case .oneOff: "One time"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .ongoing: "Ongoing"
        case .observation: "Observation"
        case .homework: "One time"
        }
    }
}
