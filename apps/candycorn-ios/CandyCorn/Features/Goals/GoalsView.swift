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
    static func sections(for goals: [Goal]) -> [GoalLedgerSectionModel] {
        GoalLedgerCadence.allCases.map { cadence in
            GoalLedgerSectionModel(cadence: cadence, goals: goals.filter { cadence.includes($0) && $0.status != .dismissed })
        }
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

struct GoalsView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = Set(GoalLedgerCadence.allCases)
    @State private var editor: GoalEditorDraft?

    var body: some View {
        ScreenLayout(
            title: "Goals",
            subtitle: "What you chose, what was assigned, and what still needs your approval.",
            backAction: navigation.backAction(for: .goals)
        ) {
            Button { editor = GoalEditorDraft() } label: {
                Label("Add goal", systemImage: "plus")
            }
            .buttonStyle(SecondaryButtonStyle())
            LazyVStack(alignment: .leading, spacing: 0) {
                Divider().overlay(DesignTokens.hairline)
                ForEach(GoalLedgerModel.sections(for: state.goals), id: \.cadence) { section in
                    GoalLedgerSection(
                        section: section,
                        isExpanded: expanded.contains(section.cadence),
                        onToggleSection: { toggle(section.cadence) },
                        onEdit: { editor = GoalEditorDraft(goal: $0) },
                        onStatus: updateStatus
                    )
                }
            }
        }
        .sheet(item: $editor) { draft in
            GoalEditorSheet(draft: draft, onCancel: { editor = nil }, onSave: save)
        }
    }

    private func toggle(_ cadence: GoalLedgerCadence) {
        withAnimation(DesignTokens.Motion.animation(reduceMotion: reduceMotion, fast: true)) {
            if expanded.contains(cadence) {
                expanded.remove(cadence)
            } else {
                expanded.insert(cadence)
            }
        }
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

private struct GoalLedgerSection: View {
    let section: GoalLedgerSectionModel
    let isExpanded: Bool
    let onToggleSection: () -> Void
    let onEdit: (Goal) -> Void
    let onStatus: (Goal, Goal.Status) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggleSection) {
                HStack(spacing: DesignTokens.Spacing.small) {
                    Text(section.cadence.rawValue)
                        .font(TypeScale.bodyMedium)
                    Spacer(minLength: DesignTokens.Spacing.small)
                    Text(section.goals.count, format: .number)
                        .font(TypeScale.label)
                        .foregroundStyle(DesignTokens.cocoaSoft)
                        .monospacedDigit()
                    AppIcon.chevronDown.image
                        .font(.system(size: 15, weight: .medium))
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .foregroundStyle(DesignTokens.cocoa)
                .frame(maxWidth: .infinity, minHeight: DesignTokens.controlMinimum)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(section.cadence.rawValue), \(section.goals.count)")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Collapses this goal group" : "Expands this goal group")

            if isExpanded {
                if section.goals.isEmpty {
                    Text("No goals here yet")
                        .font(TypeScale.label)
                        .foregroundStyle(DesignTokens.cocoaSoft)
                        .frame(maxWidth: .infinity, minHeight: DesignTokens.controlMinimum, alignment: .leading)
                        .overlay(alignment: .top) { Divider().overlay(DesignTokens.hairline) }
                } else {
                    ForEach(section.goals) { goal in
                        GoalLedgerRow(goal: goal, onEdit: { onEdit(goal) }, onStatus: { onStatus(goal, $0) })
                    }
                }
            }
            Divider().overlay(DesignTokens.hairline)
        }
    }
}

private struct GoalLedgerRow: View {
    let goal: Goal
    let onEdit: () -> Void
    let onStatus: (Goal.Status) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.small) {
            Button { onStatus(goal.status == .completed ? .active : .completed) } label: {
                ZStack {
                    Circle()
                        .fill(goal.status == .completed ? DesignTokens.sage : DesignTokens.surface)
                        .frame(width: 24, height: 24)
                    Circle()
                        .stroke(goal.status == .completed ? DesignTokens.sage : DesignTokens.cocoaSoft, lineWidth: 1)
                        .frame(width: 24, height: 24)
                    if goal.status == .completed {
                        AppIcon.check.image
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: DesignTokens.controlMinimum, height: DesignTokens.controlMinimum)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(goal.status == .completed ? "Mark incomplete" : "Mark complete"): \(goal.title)")
            .accessibilityValue(goal.status == .completed ? "Completed" : "Not completed")

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                Text(goal.title)
                    .font(TypeScale.bodyMedium)
                    .foregroundStyle(goal.status == .completed ? DesignTokens.sage : DesignTokens.cocoa)
                    .fixedSize(horizontal: false, vertical: true)
                ProvenanceLine(provenance: goal.provenance, compact: true)
            }
            .padding(.top, DesignTokens.Spacing.small)
            .padding(.bottom, DesignTokens.Spacing.compact)
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
                Image(systemName: "ellipsis")
                    .frame(width: DesignTokens.controlMinimum, height: DesignTokens.controlMinimum)
            }
            .foregroundStyle(DesignTokens.cocoa)
        }
        .overlay(alignment: .top) { Divider().overlay(DesignTokens.hairline) }
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
