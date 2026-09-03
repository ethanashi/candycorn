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
        V2Screen(
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
            ProvenanceStack(provenance: Provenance(
                voice: .candyCorn,
                label: "Candy Corn suggestions from \(entry.title)",
                detail: "Based only on the source words shown. \(artifact.provider), \(artifact.model)",
                occurredAt: artifact.createdAt,
                sourceRoute: .journalDetail
            ))
            .padding(.horizontal, DesignTokens.Spacing.xSmall)
            talkingPointCards(review.talkingPoints, entry: entry)
            commitmentCards(review.commitments, entry: entry)
        }
        if let saveError {
            StatusNotice(title: "Could not add that suggestion", detail: saveError, kind: .warning)
        }
    }

    @ViewBuilder
    private func talkingPointCards(
        _ suggestions: [JournalSignals.TalkingPointSuggestion],
        entry: JournalEntry
    ) -> some View {
        ForEach(suggestions) { suggestion in
            if decisions.isVisible(suggestion.id) {
                let added = talkingPointAdded(suggestion, entry: entry)
                V2Card {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                        cardHeader(kicker: "Talking point", title: suggestion.text, icon: .listPlus)
                        Text(suggestion.reason)
                            .font(TypeScale.label)
                            .foregroundStyle(DesignTokens.cocoaSoft)
                            .fixedSize(horizontal: false, vertical: true)
                        evidence(suggestion.evidence)
                        Button(added ? "Added" : "Add to next appointment") {
                            addTalkingPoint(suggestion, entry: entry)
                        }
                        .buttonStyle(CompactDarkButtonStyle())
                        .disabled(added || decisions.isPending(suggestion.id))
                        .accessibilityValue(added ? "Added" : "Not added")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func commitmentCards(
        _ commitments: [JournalSignals.Commitment],
        entry: JournalEntry
    ) -> some View {
        ForEach(commitments) { candidate in
            if decisions.isVisible(candidate.id) {
                V2Card {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                        cardHeader(
                            kicker: "Goal · \(cadenceTitle(JournalCandidateDraft.supportedCadence(candidate.cadenceHint)))",
                            title: candidate.text,
                            icon: .flag
                        )
                        evidence(candidate.evidence)
                        candidateActions(candidate, entry: entry)
                    }
                }
            }
        }
    }

    private func cardHeader(kicker: String, title: String, icon: AppIcon) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.compact) {
            IconTile(icon: icon, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(kicker)
                    .font(TypeScale.metaStrong)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                Text(title)
                    .font(TypeScale.cardTitle)
                    .foregroundStyle(DesignTokens.cocoa)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func candidateActions(
        _ candidate: JournalSignals.Commitment,
        entry: JournalEntry
    ) -> some View {
        let added = goalAdded(candidate, entry: entry)
        let busy = added || decisions.isPending(candidate.id)
        return HStack(spacing: DesignTokens.Spacing.small) {
            Button(added ? "Added" : "Add") {
                addGoal(JournalCandidateDraft(candidate: candidate, journalID: entry.id), entry: entry)
            }
            .buttonStyle(CompactDarkButtonStyle())
            .disabled(busy)

            Button("Edit") {
                editor = JournalCandidateDraft(candidate: candidate, journalID: entry.id)
            }
            .buttonStyle(CompactGhostButtonStyle())
            .disabled(busy)

            Button("Ignore") { decisions.ignore(candidate.id) }
                .font(TypeScale.label)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .frame(minWidth: DesignTokens.controlMinimum, minHeight: DesignTokens.controlMinimum)
                .disabled(busy)
        }
        .accessibilityElement(children: .contain)
    }

    private func evidence(_ quote: String) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.small) {
            KernelGlyph(voice: .user, height: 14, decorative: true)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your exact words")
                    .font(TypeScale.metaStrong)
                    .foregroundStyle(DesignTokens.cocoa)
                Text("“\(quote)”")
                    .font(TypeScale.meta)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DesignTokens.Spacing.compact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.surfaceWarm)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var unavailableContent: some View {
        V2GroupCard {
            if state.aiMode == .off {
                V2ListRow(icon: .sliders, title: "Organizing is off", detail: "Your journal remains available. Turn on Organizer when you want suggestions.", trailing: .none, divider: false)
            } else if !state.hasOpenRouterKey || !state.routerAvailable {
                V2ListRow(icon: .key, title: "Router key needed", detail: "Add a key in AI settings before sending journal text.", trailing: .none, divider: false)
            } else {
                V2ListRow(icon: .sparkles, title: "No usable suggestions yet", detail: "The saved suggestion artifact is missing or could not be read. Your journal is unchanged.", trailing: .none, divider: false)
            }
            V2ListRow(icon: .journal, title: "Read original") { navigation.navigate(to: .journalDetail) }
            if state.aiMode == .off || !state.hasOpenRouterKey {
                V2ListRow(icon: .sliders, title: "Open AI settings") { navigation.navigate(to: .settingsAI) }
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
