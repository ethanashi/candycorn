import SwiftUI

enum GoalLedgerCadence: String, CaseIterable, Hashable, Sendable {
    case today = "Today"
    case thisWeek = "This week"
    case thisMonth = "This month"
    case ongoing = "Ongoing"
    case homework = "Homework"

    func includes(_ goal: Goal) -> Bool {
        switch self {
        case .today: goal.cadence == .daily || goal.cadence == .oneOff
        case .thisWeek: goal.cadence == .weekly
        case .thisMonth: goal.cadence == .monthly
        case .ongoing: goal.cadence == .ongoing || goal.cadence == .observation
        case .homework: goal.cadence == .homework
        }
    }
}

struct GoalLedgerSectionModel: Equatable, Sendable {
    let cadence: GoalLedgerCadence
    let goals: [Goal]
}

enum GoalLedgerModel {
    /// Active, paused, and completed goals by cadence. Proposed goals are shown separately as suggestions.
    static func sections(for goals: [Goal]) -> [GoalLedgerSectionModel] {
        GoalLedgerCadence.allCases.map { cadence in
            GoalLedgerSectionModel(cadence: cadence, goals: goals.filter { cadence.includes($0) && $0.status != .dismissed && $0.status != .proposed })
        }
    }

    static func suggestions(for goals: [Goal]) -> [Goal] {
        goals.filter { $0.status == .proposed }
    }
}

struct GoalEditorDraft: Identifiable, Equatable, Sendable {
    let id = UUID()
    var existing: Goal?
    var title: String
    var detail: String
    var cadence: Goal.Cadence

    init(goal: Goal? = nil) {
        existing = goal
        title = goal?.title ?? ""
        detail = goal?.detail ?? ""
        cadence = goal?.cadence ?? .weekly
    }
}

/// Goals tab (v2): grouped by when, every row says who set it, suggestions sit apart and need a tap.
struct GoalsView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @State private var editor: GoalEditorDraft?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.blockGap) {
                V2TitleRow(
                    title: "Goals",
                    trailing: AnyView(RoundActionButton(icon: .plus, label: "Add goal", dark: true) {
                        editor = GoalEditorDraft()
                    })
                )
                ForEach(visibleSections, id: \.cadence) { section in
                    SectionLine(title: section.cadence.rawValue, trailing: trailingText(for: section))
                    V2Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(section.goals.enumerated()), id: \.element.id) { index, goal in
                                if index > 0 { Rectangle().fill(DesignTokens.hairline).frame(height: 1).padding(.horizontal, DesignTokens.Spacing.base) }
                                GoalRow(goal: goal, onEdit: { editor = GoalEditorDraft(goal: goal) }, onStatus: { updateStatus(goal, $0) })
                            }
                        }
                    }
                }
                if !suggestions.isEmpty {
                    SectionLine(title: "Needs your yes", trailing: "\(suggestions.count) \(suggestions.count == 1 ? "suggestion" : "suggestions")")
                    ForEach(suggestions) { goal in
                        SuggestionCard(goal: goal, onAdd: { updateStatus(goal, .active) }, onDismiss: { updateStatus(goal, .dismissed) })
                    }
                }
                if visibleSections.isEmpty && suggestions.isEmpty {
                    V2Card(background: DesignTokens.surfaceWarm, showsBorder: false) {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                            Text("No goals yet").font(TypeScale.cardTitle).foregroundStyle(DesignTokens.cocoa)
                            Text("Add one, or let a journal entry suggest one you can accept.")
                                .font(TypeScale.label).foregroundStyle(DesignTokens.cocoaSoft)
                        }
                    }
                }
                Button {
                    navigation.navigate(to: .bringUp)
                } label: {
                    HStack(spacing: DesignTokens.Spacing.compact) {
                        IconTile(icon: .flag, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bring up next time")
                                .font(TypeScale.rowTitle)
                                .foregroundStyle(DesignTokens.cocoa)
                            Text("\(openTalkingPoints) pinned for your next appointment")
                                .font(TypeScale.meta)
                                .foregroundStyle(DesignTokens.cocoaSoft)
                        }
                        Spacer()
                        AppIcon.chevronRight.image
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DesignTokens.cocoaSoft)
                    }
                    .padding(DesignTokens.Spacing.base)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DesignTokens.surface)
                    .overlay(RoundedRectangle(cornerRadius: DesignTokens.v2CardRadius, style: .continuous).stroke(DesignTokens.hairline, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.v2CardRadius, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bring up next time, \(openTalkingPoints) pinned")
            }
            .padding(.horizontal, DesignTokens.screenInset)
            .padding(.top, DesignTokens.Spacing.small)
            .padding(.bottom, DesignTokens.tabBarClearance)
        }
        .background(DesignTokens.canvas.ignoresSafeArea())
        .sheet(item: $editor) { draft in
            GoalEditorSheet(draft: draft, onCancel: { editor = nil }, onSave: save)
        }
    }

    private var visibleSections: [GoalLedgerSectionModel] {
        GoalLedgerModel.sections(for: state.goals).filter { !$0.goals.isEmpty }
    }

    private var suggestions: [Goal] { GoalLedgerModel.suggestions(for: state.goals) }

    private var openTalkingPoints: Int { state.talkingPoints.filter { $0.status == .open }.count }

    private func trailingText(for section: GoalLedgerSectionModel) -> String {
        let done = section.goals.filter { $0.status == .completed }.count
        if section.cadence == .homework, let goal = section.goals.first, let date = goal.targetDate {
            return "Due \(date.formatted(.dateTime.weekday(.abbreviated)))"
        }
        return done > 0 ? "\(done) of \(section.goals.count) done" : "\(section.goals.count)"
    }

    private func updateStatus(_ goal: Goal, _ status: Goal.Status) {
        Task { _ = await state.transitionGoal(id: goal.id, to: status) }
    }

    private func save(_ draft: GoalEditorDraft) async -> Bool {
        let trimmed = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let goal: Goal
        if var existing = draft.existing {
            existing.title = trimmed
            existing.detail = draft.detail.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            existing.cadence = draft.cadence
            goal = existing
        } else {
            let now = state.dependencies.now()
            goal = Goal(
                id: UUID(), title: trimmed,
                detail: draft.detail.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                cadence: draft.cadence, source: .userExplicit, sourceEntityID: nil,
                sourceTimestampMilliseconds: nil, status: .active, createdAt: now, targetDate: nil,
                provenance: Provenance(voice: .user, label: "You chose this", detail: "Created in Goals", occurredAt: now, sourceRoute: .goals)
            )
        }
        return await state.saveGoal(goal)
    }
}

private struct GoalRow: View {
    let goal: Goal
    let onEdit: () -> Void
    let onStatus: (Goal.Status) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.compact) {
            Button { onStatus(goal.status == .completed ? .active : .completed) } label: {
                CompletionCircle(done: goal.status == .completed)
                    .frame(width: DesignTokens.controlMinimum, height: DesignTokens.controlMinimum)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(goal.status == .completed ? "Mark not done" : "Mark done"): \(goal.title)")

            VStack(alignment: .leading, spacing: 3) {
                Text(goal.title)
                    .font(TypeScale.rowTitle)
                    .foregroundStyle(DesignTokens.cocoa)
                    .strikethrough(goal.status == .completed, color: DesignTokens.cocoaSoft)
                    .fixedSize(horizontal: false, vertical: true)
                ProvenanceInline(voice: goal.provenance.voice, text: goal.provenance.inlineText + (goal.status == .paused ? " · paused" : ""))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Button("Edit", action: onEdit)
                if goal.status == .paused {
                    Button("Resume") { onStatus(.active) }
                } else {
                    Button("Pause") { onStatus(.paused) }
                }
                Button("Dismiss", role: .destructive) { onStatus(.dismissed) }
            } label: {
                AppIcon.ellipsis.image
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .frame(width: DesignTokens.controlMinimum, height: DesignTokens.controlMinimum)
            }
            .accessibilityLabel("More options for \(goal.title)")
        }
        .padding(.horizontal, DesignTokens.Spacing.base)
        .padding(.vertical, DesignTokens.Spacing.small)
        .frame(minHeight: 60)
    }
}

private struct SuggestionCard: View {
    let goal: Goal
    let onAdd: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        V2Card(background: DesignTokens.surfaceWarm, showsBorder: false) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                ProvenanceInline(voice: .candyCorn, text: goal.provenance.detail.isEmpty ? "Found in your journal" : goal.provenance.detail)
                Text(goal.title)
                    .font(TypeScale.rowTitle)
                    .foregroundStyle(DesignTokens.cocoa)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = goal.detail, !detail.isEmpty {
                    Text(detail)
                        .font(TypeScale.provenance)
                        .foregroundStyle(DesignTokens.cocoaSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: DesignTokens.Spacing.small) {
                    Button("Add as goal", action: onAdd)
                        .buttonStyle(CompactDarkButtonStyle())
                    Button("Not now", action: onDismiss)
                        .buttonStyle(CompactGhostButtonStyle())
                }
                .padding(.top, DesignTokens.Spacing.xSmall)
            }
        }
    }
}

struct CompactDarkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeScale.label)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(minHeight: DesignTokens.controlMinimum)
            .background(DesignTokens.cocoa.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct CompactGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeScale.label)
            .foregroundStyle(DesignTokens.cocoa)
            .padding(.horizontal, 18)
            .frame(minHeight: DesignTokens.controlMinimum)
            .background(configuration.isPressed ? DesignTokens.surfaceWarm : Color.white)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DesignTokens.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct GoalEditorSheet: View {
    @State var draft: GoalEditorDraft
    @State private var isSaving = false
    let onCancel: () -> Void
    let onSave: (GoalEditorDraft) async -> Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Goal", text: $draft.title)
                TextField("Optional detail", text: $draft.detail, axis: .vertical)
                Picker("Cadence", selection: $draft.cadence) {
                    ForEach(Goal.Cadence.allCases, id: \.self) { cadence in
                        Text(cadence.title).tag(cadence)
                    }
                }
            }
            .navigationTitle(draft.existing == nil ? "Add goal" : "Edit goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Save") {
                        guard !isSaving else { return }
                        isSaving = true
                        Task {
                            if await onSave(draft) { onCancel() }
                            isSaving = false
                        }
                    }
                    .disabled(isSaving || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension Goal.Cadence {
    var title: String {
        switch self {
        case .oneOff: "One time"
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .ongoing: "Ongoing"
        case .observation: "Observation"
        case .homework: "Homework"
        }
    }
}
