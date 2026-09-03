import SwiftUI

enum TodaySectionKind: Equatable, Sendable {
    case appointment
    case talkingPoint(UUID)
    case currentGoal(UUID)
}

enum TodayOrderingModel {
    static func sections(talkingPoints: [TalkingPoint], currentGoal: Goal?) -> [TodaySectionKind] {
        var result: [TodaySectionKind] = [.appointment]
        result.append(contentsOf: talkingPoints.filter { $0.status == .open }.prefix(3).map { .talkingPoint($0.id) })
        if let currentGoal { result.append(.currentGoal(currentGoal.id)) }
        return result
    }
}

struct TodayView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                context
                Text("Today")
                    .font(TypeScale.pageTitle)
                    .foregroundStyle(DesignTokens.cocoa)
                    .padding(.top, DesignTokens.Spacing.compact)
                moodSection
                    .padding(.top, DesignTokens.Spacing.medium)
                captureActions
                    .padding(.top, DesignTokens.Spacing.medium)
                appointment
                    .padding(.top, DesignTokens.Spacing.large)
                ledger
                    .padding(.top, DesignTokens.Spacing.large)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.screenInset)
            .padding(.top, DesignTokens.Spacing.compact)
            .padding(.bottom, 128)
        }
        .background(DesignTokens.canvas.ignoresSafeArea())
    }

    private var context: some View {
        HStack {
            Text(state.dependencies.now().formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .monospacedDigit()
            Spacer()
            Text("Jamie")
                .font(TypeScale.label)
                .foregroundStyle(DesignTokens.cocoa)
        }
        .font(TypeScale.label)
        .foregroundStyle(DesignTokens.cocoaSoft)
        .accessibilityElement(children: .combine)
    }

    private var moodSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("How are you doing?")
                .font(TypeScale.question)
                .foregroundStyle(DesignTokens.cocoa)
            if state.mood == nil {
                Text("No check-in yet")
                    .font(TypeScale.label)
                    .foregroundStyle(DesignTokens.cocoaSoft)
            }
            Button { navigation.navigate(to: .checkIn) } label: {
                MoodBands(values: moodValues)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open quick mood check-in")
            .accessibilityValue(moodAccessibilityValue)
        }
    }

    @ViewBuilder private var captureActions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: DesignTokens.Spacing.small) { actionButtons }
        } else {
            HStack(spacing: DesignTokens.Spacing.small) { actionButtons }
        }
    }

    @ViewBuilder private var actionButtons: some View {
        TodayActionButton(title: "Talk", icon: .microphone, prominent: true) {
            navigation.navigate(to: .journalVoice)
        }
        TodayActionButton(title: "Write", icon: .pencil) {
            navigation.navigate(to: .journalWrite)
        }
        TodayActionButton(title: "Record appointment", icon: .calendar) {
            navigation.navigate(to: .recordAppointment)
        }
    }

    private var appointment: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            sectionHeading("Next appointment", actionTitle: appointmentDateLabel, action: nil)
            Button {
                if let id = nextAppointment?.id { state.selectAppointment(id: id) }
                navigation.navigate(to: .appointments)
            } label: {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
                    Text(appointmentTitle)
                        .font(TypeScale.bodyMedium)
                        .foregroundStyle(DesignTokens.cocoa)
                    Text(appointmentTimeLabel)
                        .font(TypeScale.label)
                        .foregroundStyle(DesignTokens.cocoaSoft)
                    if let appointment = nextAppointment {
                        ProvenanceLine(
                            provenance: Provenance(
                                voice: .provider,
                                label: "Provider appointment scheduled",
                                detail: appointment.scheduledAt?.formatted(date: .abbreviated, time: .shortened) ?? "Time not set",
                                occurredAt: appointment.scheduledAt,
                                sourceRoute: .appointments
                            ),
                            compact: true
                        )
                        .padding(.top, DesignTokens.Spacing.small)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
                .padding(.horizontal, DesignTokens.Spacing.base)
                .background(DesignTokens.surface)
                .overlay(cardBorder)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(appointmentTitle), \(appointmentTimeLabel)")
            .accessibilityHint("Opens appointments")
        }
    }

    private var ledger: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
            let openPoints = Array(state.talkingPoints.filter { $0.status == .open }.prefix(3))
            if !openPoints.isEmpty {
                TalkingPointLedgerSection(points: openPoints) {
                    navigation.navigate(to: .bringUp)
                }
            }
            if let goal = currentGoal {
                LedgerSection(title: "Current goal", actionTitle: "See goals", itemTitle: goal.title, provenance: goal.provenance) {
                    navigation.navigate(to: .goals)
                }
            }
            if let journal = state.journals.max(by: { $0.updatedAt < $1.updatedAt }) {
                LedgerSection(
                    title: "Recent memory",
                    actionTitle: nil,
                    itemTitle: journal.title,
                    provenance: journal.provenance
                ) {
                    state.selectJournal(id: journal.id)
                    navigation.navigate(to: .journalDetail)
                }
            }
        }
    }

    private var moodValues: MoodValues {
        MoodValues(mood: state.mood?.mood, anxiety: state.mood?.anxiety, energy: state.mood?.energy)
    }

    private var moodAccessibilityValue: String {
        guard let mood = state.mood else { return "No check-in yet. Anxiety, mood, and energy not logged" }
        return "Anxiety \(mood.anxiety.map(String.init) ?? "not logged"), mood \(mood.mood.map(String.init) ?? "not logged"), energy \(mood.energy.map(String.init) ?? "not logged")"
    }

    private var currentGoal: Goal? {
        let active = state.goals.filter { $0.status == .active || $0.status == .proposed }
        return active.first { $0.cadence == .daily } ?? active.first
    }

    private var nextAppointment: Appointment? {
        state.appointments.filter { $0.status == .planned }.min {
            ($0.scheduledAt ?? .distantFuture) < ($1.scheduledAt ?? .distantFuture)
        }
    }

    private var appointmentTitle: String {
        guard let appointment = nextAppointment else { return "No appointment scheduled" }
        return "\(appointment.kind.displayName) with \(appointment.providerName)"
    }

    private var appointmentDateLabel: String? {
        nextAppointment?.scheduledAt?.formatted(.dateTime.month(.abbreviated).day())
    }

    private var appointmentTimeLabel: String {
        nextAppointment?.scheduledAt?.formatted(.dateTime.weekday(.wide).hour().minute()) ?? "Add a visit when you are ready"
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
            .stroke(DesignTokens.hairline, lineWidth: 1)
    }

    private func sectionHeading(_ title: String, actionTitle: String?, action: (() -> Void)?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(TypeScale.sectionCompact)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(TypeScale.provenance)
                    .frame(minHeight: DesignTokens.controlMinimum)
            } else if let actionTitle {
                Text(actionTitle).font(TypeScale.provenance).monospacedDigit()
            }
        }
        .foregroundStyle(DesignTokens.cocoa)
    }
}

private struct TodayActionButton: View {
    let title: String
    let icon: AppIcon
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: DesignTokens.Spacing.xSmall) {
                icon.image.font(.system(size: 21, weight: .medium))
                Text(title)
                    .font(TypeScale.label)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(DesignTokens.cocoa)
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.horizontal, DesignTokens.Spacing.xSmall)
            .background(prominent ? DesignTokens.orange : DesignTokens.surface)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous)
                    .stroke(prominent ? DesignTokens.orange : DesignTokens.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct LedgerSection: View {
    let title: String
    let actionTitle: String?
    let itemTitle: String
    let provenance: Provenance
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(TypeScale.sectionCompact)
                Spacer()
                if let actionTitle {
                    Button(action: action) {
                        HStack(spacing: DesignTokens.Spacing.xSmall) {
                            Text(actionTitle)
                            Image(systemName: "chevron.right")
                        }
                        .font(TypeScale.provenance)
                        .foregroundStyle(DesignTokens.cocoa)
                        .frame(minHeight: DesignTokens.controlMinimum)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button(action: action) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                    Text(itemTitle)
                        .font(TypeScale.bodyMedium)
                        .foregroundStyle(DesignTokens.cocoa)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ProvenanceLine(provenance: provenance, compact: true)
                }
                .padding(.vertical, DesignTokens.Spacing.base)
                .overlay(alignment: .top) { Divider().overlay(DesignTokens.hairline) }
                .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(itemTitle). \(provenance.label). \(provenance.detail)")
        }
    }
}

private struct TalkingPointLedgerSection: View {
    let points: [TalkingPoint]
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text("Bring up next time").font(TypeScale.sectionCompact)
                Spacer()
                Button(action: action) {
                    HStack(spacing: DesignTokens.Spacing.xSmall) {
                        Text("Open inbox")
                        Image(systemName: "chevron.right")
                    }
                    .font(TypeScale.provenance)
                    .foregroundStyle(DesignTokens.cocoa)
                    .frame(minHeight: DesignTokens.controlMinimum)
                }
                .buttonStyle(.plain)
            }
            ForEach(points) { point in
                Button(action: action) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        Text(point.text)
                            .font(TypeScale.bodyMedium)
                            .foregroundStyle(DesignTokens.cocoa)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ProvenanceLine(provenance: point.provenance, compact: true)
                    }
                    .padding(.vertical, DesignTokens.Spacing.compact)
                    .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
