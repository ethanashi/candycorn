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
            GoalLedgerSectionModel(cadence: cadence, goals: goals.filter(cadence.includes))
        }
    }
}

struct GoalsView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = Set(GoalLedgerCadence.allCases)

    var body: some View {
        ScreenLayout(
            title: "Goals",
            subtitle: "What you chose, what was assigned, and what still needs your approval.",
            backAction: navigation.backAction(for: .goals)
        ) {
            LazyVStack(alignment: .leading, spacing: 0) {
                Divider().overlay(DesignTokens.hairline)
                ForEach(GoalLedgerModel.sections(for: state.goals), id: \.cadence) { section in
                    GoalLedgerSection(
                        section: section,
                        isExpanded: expanded.contains(section.cadence),
                        onToggleSection: { toggle(section.cadence) },
                        onToggleGoal: state.toggleGoal
                    )
                }
            }
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
}

private struct GoalLedgerSection: View {
    let section: GoalLedgerSectionModel
    let isExpanded: Bool
    let onToggleSection: () -> Void
    let onToggleGoal: (UUID) -> Void

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
                        GoalLedgerRow(goal: goal) { onToggleGoal(goal.id) }
                    }
                }
            }
            Divider().overlay(DesignTokens.hairline)
        }
    }
}

private struct GoalLedgerRow: View {
    let goal: Goal
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.small) {
            Button(action: onToggle) {
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
        }
        .overlay(alignment: .top) { Divider().overlay(DesignTokens.hairline) }
    }
}
