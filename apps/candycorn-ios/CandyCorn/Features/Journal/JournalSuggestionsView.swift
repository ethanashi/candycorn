import SwiftUI

struct JournalSuggestionsView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @State private var decisions = JournalCandidateDecisions()
    @State private var editor: JournalCandidateDraft?
    @State private var saveError: String?

    private var entry: JournalEntry? {
        if let id = state.selectedJournalID {
            return state.journals.first { $0.id == id }
        }
        return state.journals.max { $0.updatedAt < $1.updatedAt }
    }

    private var decodedSignals: (artifact: AIArtifact, result: JournalSignalResult)? {
        guard let entry else { return nil }
        return JournalArtifactReader.decode(
            JournalSignalResult.self,
            kind: .journalSignals,
            journal: entry,
            artifacts: state.artifacts
        )
    }

    var body: some View {
        ScreenLayout(
            title: "Suggestions",
            subtitle: "Nothing is added until you choose it.",
            backAction: navigation.backAction(for: .journalSuggestions)
        ) {
            if let entry, let decodedSignals {
                suggestionLedger(
                    JournalSuggestionReview(signals: decodedSignals.result.signals),
                    entry: entry,
                    artifact: decodedSignals.artifact
                )
            } else if entry == nil {
                StatusNotice(
                    title: "No journal selected",
                    detail: "Open a journal entry to review its possible next steps.",
                    kind: .information
                )
            } else {
                unavailableContent
            }
        }
        .sheet(item: $editor) { draft in
            JournalCandidateEditor(
                draft: draft,
                onCancel: { editor = nil },
                onAdd: addEditedGoal
            )
        }
    }

    @ViewBuilder
    private func suggestionLedger(
        _ review: JournalSuggestionReview,
        entry: JournalEntry,
        artifact: AIArtifact
    ) -> some View {
        if review.talkingPoints.isEmpty && review.commitments.isEmpty {
            StatusNotice(
                title: "No explicit next steps found",
                detail: "Candy Corn did not find a commitment or talking point supported by this journal.",
                kind: .information
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ledgerHeader(artifact: artifact)
                talkingPointRows(review.talkingPoints, entry: entry, artifact: artifact)
                commitmentRows(review.commitments, entry: entry, artifact: artifact)
            }
            .padding(DesignTokens.Spacing.base)
            .background(DesignTokens.surfaceWarm)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
        }
        if let saveError {
            StatusNotice(title: "Could not add that suggestion", detail: saveError, kind: .warning)
        }
    }

    private func ledgerHeader(artifact: AIArtifact) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("Possible next steps")
                .font(TypeScale.section)
                .foregroundStyle(DesignTokens.cocoa)
            Text("Suggestions are based only on source words shown below.")
                .font(TypeScale.label)
                .foregroundStyle(DesignTokens.cocoaSoft)
            candyCornProvenance(
                label: "Candy Corn suggestions",
                detail: "\(artifact.provider), \(artifact.model)",
                occurredAt: artifact.createdAt
            )
        }
        .padding(.bottom, DesignTokens.Spacing.medium)
    }

    @ViewBuilder
    private func talkingPointRows(
        _ suggestions: [JournalSignals.TalkingPointSuggestion],
        entry: JournalEntry,
        artifact: AIArtifact
    ) -> some View {
        ForEach(suggestions) { suggestion in
            if decisions.isVisible(suggestion.id) {
                Divider().overlay(DesignTokens.hairline)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                    candyCornProvenance(
                        label: "Candy Corn suggested a talking point",
                        detail: "From \(entry.title)",
                        occurredAt: artifact.createdAt
                    )
                    Text(suggestion.text)
                        .font(TypeScale.bodyMedium)
                        .foregroundStyle(DesignTokens.cocoa)
                    Text(suggestion.reason)
                        .font(TypeScale.body)
                        .foregroundStyle(DesignTokens.cocoaSoft)
                    evidence(suggestion.evidence)
                    Button {
                        addTalkingPoint(suggestion, entry: entry)
                    } label: {
                        Label(
                            talkingPointAdded(suggestion, entry: entry) ? "Added" : "Add to next appointment",
                            systemImage: talkingPointAdded(suggestion, entry: entry) ? AppIcon.check.rawValue : AppIcon.listPlus.rawValue
                        )
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(talkingPointAdded(suggestion, entry: entry) || decisions.isPending(suggestion.id))
                    .accessibilityValue(talkingPointAdded(suggestion, entry: entry) ? "Added" : "Not added")
                }
                .padding(.vertical, DesignTokens.Spacing.medium)
            }
        }
    }

    @ViewBuilder
    private func commitmentRows(
        _ commitments: [JournalSignals.Commitment],
        entry: JournalEntry,
        artifact: AIArtifact
    ) -> some View {
        ForEach(commitments) { candidate in
            if decisions.isVisible(candidate.id) {
                Divider().overlay(DesignTokens.hairline)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                    candyCornProvenance(
                        label: "Candy Corn found an explicit commitment",
                        detail: "Candidate goal from \(entry.title)",
                        occurredAt: artifact.createdAt
                    )
                    Text(candidate.text)
                        .font(TypeScale.bodyMedium)
                        .foregroundStyle(DesignTokens.cocoa)
                    Text("Suggested cadence: \(cadenceTitle(JournalCandidateDraft.supportedCadence(candidate.cadenceHint)))")
                        .font(TypeScale.label)
                        .foregroundStyle(DesignTokens.cocoaSoft)
                    evidence(candidate.evidence)
                    candidateActions(candidate, entry: entry)
                }
                .padding(.vertical, DesignTokens.Spacing.medium)
            }
        }
    }

    private func candidateActions(
        _ candidate: JournalSignals.Commitment,
        entry: JournalEntry
    ) -> some View {
        let added = goalAdded(candidate, entry: entry)
        return HStack(spacing: DesignTokens.Spacing.small) {
            Button(added ? "Added" : "Add") {
                addGoal(JournalCandidateDraft(candidate: candidate, journalID: entry.id), entry: entry)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.orange)
            .foregroundStyle(DesignTokens.cocoa)
            .frame(minHeight: DesignTokens.controlMinimum)
            .disabled(added || decisions.isPending(candidate.id))

            Button("Edit") {
                editor = JournalCandidateDraft(candidate: candidate, journalID: entry.id)
            }
            .buttonStyle(.bordered)
            .tint(DesignTokens.cocoa)
            .frame(minHeight: DesignTokens.controlMinimum)
            .disabled(added || decisions.isPending(candidate.id))

            Button("Ignore") { decisions.ignore(candidate.id) }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .frame(minWidth: DesignTokens.controlMinimum, minHeight: DesignTokens.controlMinimum)
                .disabled(added || decisions.isPending(candidate.id))
        }
        .accessibilityElement(children: .contain)
    }

    private func evidence(_ quote: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
            Text("Your exact words")
                .font(TypeScale.provenance)
                .foregroundStyle(DesignTokens.yellowText)
            Text("“\(quote)”")
                .font(TypeScale.label)
                .foregroundStyle(DesignTokens.cocoa)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var unavailableContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.base) {
            if state.aiMode == .off {
                StatusNotice(
                    title: "Organizing is off",
                    detail: "Your journal remains available. Turn on Organizer when you want suggestions.",
                    kind: .information
                )
            } else if !state.hasOpenRouterKey || !state.routerAvailable {
                StatusNotice(
                    title: "Router key needed",
                    detail: "Add a key in AI settings before sending journal text.",
                    kind: .warning
                )
            } else {
                StatusNotice(
                    title: "No usable suggestions yet",
                    detail: "The saved suggestion artifact is missing or could not be read. Your journal is unchanged.",
                    kind: .warning
                )
            }
            Button("Read original") { navigation.navigate(to: .journalDetail) }
                .buttonStyle(SecondaryButtonStyle())
            if state.aiMode == .off || !state.hasOpenRouterKey {
                Button("Open AI settings") { navigation.navigate(to: .settingsAI) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func addTalkingPoint(
        _ suggestion: JournalSignals.TalkingPointSuggestion,
        entry: JournalEntry
    ) {
        guard decisions.begin(suggestion.id), !talkingPointAdded(suggestion, entry: entry) else { return }
        saveError = nil
        let now = state.dependencies.now()
        let point = JournalSuggestionFactory.talkingPoint(
            from: suggestion,
            journalID: entry.id,
            sourceTitle: entry.title,
            target: nextAppointmentKind(),
            now: now
        )
        Task {
            guard let point, await state.saveTalkingPoint(point) else {
                saveError = "The talking point was not added. Try again."
                decisions.finish(suggestion.id)
                return
            }
            decisions.finish(suggestion.id)
        }
    }

    private func addGoal(_ draft: JournalCandidateDraft, entry: JournalEntry) {
        guard decisions.begin(draft.id), !goalAdded(id: draft.id, title: draft.title, entry: entry) else { return }
        saveError = nil
        Task {
            guard let goal = draft.makeGoal(now: state.dependencies.now(), sourceTitle: entry.title),
                  await state.saveGoal(goal) else {
                saveError = "The goal was not added. Check its title and try again."
                decisions.finish(draft.id)
                return
            }
            decisions.finish(draft.id)
        }
    }

    private func addEditedGoal(_ draft: JournalCandidateDraft) async -> Bool {
        guard let entry, decisions.begin(draft.id),
              !goalAdded(id: draft.id, title: draft.title, entry: entry),
              let goal = draft.makeGoal(now: state.dependencies.now(), sourceTitle: entry.title) else {
            return false
        }
        let saved = await state.saveGoal(goal)
        decisions.finish(draft.id)
        if !saved { saveError = "The edited goal was not added. Try again." }
        return saved
    }

    private func talkingPointAdded(
        _ suggestion: JournalSignals.TalkingPointSuggestion,
        entry: JournalEntry
    ) -> Bool {
        let normalized = suggestion.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return state.talkingPoints.contains {
            $0.id == suggestion.id || ($0.sourceID == entry.id && $0.source == .aiSuggestion
                && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized)
        }
    }

    private func goalAdded(_ candidate: JournalSignals.Commitment, entry: JournalEntry) -> Bool {
        goalAdded(id: candidate.id, title: candidate.text, entry: entry)
    }

    private func goalAdded(id: UUID, title: String, entry: JournalEntry) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return state.goals.contains {
            $0.id == id || ($0.sourceEntityID == entry.id && $0.source == .aiSuggested
                && $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized)
        }
    }

    private func nextAppointmentKind() -> Appointment.Kind {
        state.appointments
            .filter { $0.status == .planned }
            .sorted { ($0.scheduledAt ?? .distantFuture) < ($1.scheduledAt ?? .distantFuture) }
            .first?.kind ?? .therapy
    }

    private func candyCornProvenance(label: String, detail: String, occurredAt: Date?) -> ProvenanceLine {
        ProvenanceLine(provenance: Provenance(
            voice: .candyCorn,
            label: label,
            detail: detail,
            occurredAt: occurredAt,
            sourceRoute: .journalDetail
        ))
    }

    private func cadenceTitle(_ cadence: Goal.Cadence) -> String {
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
