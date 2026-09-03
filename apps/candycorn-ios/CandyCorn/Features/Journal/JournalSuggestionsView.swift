import SwiftUI

enum JournalSuggestionFixtures {
    static let provenance = Provenance(
        voice: .candyCorn,
        label: "Candy Corn suggested this",
        detail: "Based on your Sep 5 journal. Nothing is added until you choose it.",
        occurredAt: Date(timeIntervalSince1970: 1_788_646_800),
        sourceRoute: .journalDetail
    )

    static let proofPoint = TalkingPoint(
        id: id("51000000-0000-0000-0000-000000000001"),
        text: "What would it mean now to stop needing proof that I could have played?",
        source: .aiSuggestion,
        sourceID: SeededData.footballJournalID,
        targetAppointmentKind: .therapy,
        isImportant: true,
        status: .open,
        createdAt: Date(timeIntervalSince1970: 1_788_646_800),
        provenance: provenance
    )

    static let guiltPoint = TalkingPoint(
        id: id("51000000-0000-0000-0000-000000000002"),
        text: "Why can feeling better bring up guilt about moving forward?",
        source: .aiSuggestion,
        sourceID: SeededData.footballJournalID,
        targetAppointmentKind: .therapy,
        isImportant: false,
        status: .open,
        createdAt: Date(timeIntervalSince1970: 1_788_646_800),
        provenance: provenance
    )

    static let goal = Goal(
        id: id("41000000-0000-0000-0000-000000000001"),
        title: "Notice one moment when relief is followed by guilt",
        detail: nil,
        cadence: .weekly,
        source: .aiSuggested,
        sourceEntityID: SeededData.footballJournalID,
        sourceTimestampMilliseconds: nil,
        status: .active,
        createdAt: Date(timeIntervalSince1970: 1_788_646_800),
        targetDate: nil,
        provenance: provenance
    )

    static let talkingPoints = [proofPoint, guiltPoint]

    private static func id(_ value: String) -> UUID {
        guard let identifier = UUID(uuidString: value) else {
            preconditionFailure("Journal suggestion UUID must be valid")
        }
        return identifier
    }
}

struct JournalSuggestionsView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @State private var retryAttempted = false
    @State private var pendingIDs: Set<UUID> = []

    var body: some View {
        ScreenLayout(
            title: "Suggestions",
            subtitle: "Nothing here changes your original.",
            backAction: navigation.backAction(for: .journalSuggestions)
        ) {
            if state.aiMode == .off {
                unavailableCard(
                    title: "Organizing is off",
                    detail: "Your original journal is still readable and safe.",
                    showsRetry: false
                )
            } else if !state.routerAvailable {
                unavailableCard(
                    title: "Organization is unavailable",
                    detail: "Your original is safe. Trying again does not change it.",
                    showsRetry: true
                )
            } else {
                suggestionRegion
            }
        }
    }

    private var suggestionRegion: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Possible next steps")
                .font(TypeScale.section)
            Text("These are suggestions, not advice. Add only what feels useful.")
                .font(TypeScale.label)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .padding(.top, DesignTokens.Spacing.xSmall)

            ForEach(Array(JournalSuggestionFixtures.talkingPoints.enumerated()), id: \.element.id) { index, point in
                suggestionDivider(show: index > 0)
                suggestionRow(
                    provenance: point.provenance,
                    text: point.text,
                    added: state.talkingPoints.contains { $0.id == point.id },
                    pending: pendingIDs.contains(point.id),
                    action: "Add to next appointment"
                ) {
                    save(point)
                }
            }

            suggestionDivider(show: true)
            suggestionRow(
                provenance: JournalSuggestionFixtures.goal.provenance,
                text: JournalSuggestionFixtures.goal.title,
                added: state.goals.contains { $0.id == JournalSuggestionFixtures.goal.id },
                pending: pendingIDs.contains(JournalSuggestionFixtures.goal.id),
                action: "Add as a goal"
            ) {
                save(JournalSuggestionFixtures.goal)
            }
        }
        .padding(DesignTokens.Spacing.base)
        .background(DesignTokens.surfaceWarm)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
    }

    private func suggestionRow(
        provenance: Provenance,
        text: String,
        added: Bool,
        pending: Bool,
        action: String,
        onAdd: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            ProvenanceLine(provenance: provenance)
            Text(text)
                .font(TypeScale.body)
                .foregroundStyle(DesignTokens.cocoa)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onAdd) {
                HStack(spacing: DesignTokens.Spacing.small) {
                    if added { Image(systemName: AppIcon.check.rawValue) }
                    Text(added ? "Added" : pending ? "Saving" : action)
                }
                .font(TypeScale.label)
                .foregroundStyle(added ? DesignTokens.sage : DesignTokens.cocoa)
                .frame(minHeight: DesignTokens.controlMinimum)
                .padding(.horizontal, DesignTokens.Spacing.compact)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(added ? DesignTokens.sage : DesignTokens.cocoa, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(added || pending)
            .accessibilityValue(added ? "Added" : "Not added")
        }
    }

    private func save(_ point: TalkingPoint) {
        guard pendingIDs.insert(point.id).inserted else { return }
        Task {
            _ = await state.saveTalkingPoint(point)
            pendingIDs.remove(point.id)
        }
    }

    private func save(_ goal: Goal) {
        guard pendingIDs.insert(goal.id).inserted else { return }
        Task {
            _ = await state.saveGoal(goal)
            pendingIDs.remove(goal.id)
        }
    }

    @ViewBuilder
    private func suggestionDivider(show: Bool) -> some View {
        if show {
            Divider()
                .overlay(DesignTokens.hairline)
                .padding(.vertical, DesignTokens.Spacing.medium)
        } else {
            Spacer().frame(height: DesignTokens.Spacing.medium)
        }
    }

    private func unavailableCard(title: String, detail: String, showsRetry: Bool) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            StatusNotice(title: title, detail: detail, kind: showsRetry ? .warning : .information)
            if showsRetry {
                Button(retryAttempted ? "Still unavailable" : "Try again") {
                    retryAttempted = true
                }
                .font(TypeScale.label)
                .foregroundStyle(DesignTokens.cocoa)
                .frame(minHeight: DesignTokens.controlMinimum)
                .padding(.horizontal, DesignTokens.Spacing.compact)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(DesignTokens.cocoa, lineWidth: 1))
                .buttonStyle(.plain)
            }
            Button("Read original") {
                navigation.navigate(to: .journalDetail)
            }
            .frame(minHeight: DesignTokens.controlMinimum)
            .font(TypeScale.bodyMedium)

            if !showsRetry {
                Button("Open AI settings") {
                    navigation.navigate(to: .settingsAI)
                }
                .frame(minHeight: DesignTokens.controlMinimum)
                .font(TypeScale.bodyMedium)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
