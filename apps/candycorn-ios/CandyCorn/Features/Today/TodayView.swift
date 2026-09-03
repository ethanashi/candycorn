import SwiftUI

/// Today, on the Flo skeleton approved September 2, 2026 (docs/design/v2/today.html).
/// One dominant object (Talk), then how you are, the next appointment, and one goal.
/// The composition fills the space above the tab bar; the hero absorbs the slack.
struct TodayView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Fixed heights of every block except the hero, plus the gaps and paddings around them.
    private static let headerHeight: CGFloat = 36
    private static let weekHeight: CGFloat = 60
    private static let moodHeight: CGFloat = 80
    private static let appointmentHeight: CGFloat = 82
    private static let upNextHeight: CGFloat = 96
    private static var fixedTotal: CGFloat {
        headerHeight + weekHeight + moodHeight + appointmentHeight + upNextHeight
            + DesignTokens.blockGap * 5 + DesignTokens.Spacing.small + DesignTokens.blockGap
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    blocks(heroHeight: 240)
                        .padding(.bottom, DesignTokens.Spacing.large)
                }
            } else {
                GeometryReader { geometry in
                    blocks(heroHeight: max(200, geometry.size.height - Self.fixedTotal - DesignTokens.tabBarReserved))
                }
            }
        }
        .background(DesignTokens.canvas.ignoresSafeArea())
    }

    private func blocks(heroHeight: CGFloat) -> some View {
        VStack(spacing: DesignTokens.blockGap) {
            header
                .frame(height: Self.headerHeight)
            WeekStrip(today: now, markedDays: markedDays)
                .frame(height: Self.weekHeight)
            hero
                .frame(height: heroHeight)
            moodCard
                .frame(height: Self.moodHeight)
            appointmentBand
                .frame(height: Self.appointmentHeight)
            upNextCard
                .frame(height: Self.upNextHeight)
        }
        .padding(.horizontal, DesignTokens.screenInset)
        .padding(.top, DesignTokens.Spacing.small)
        .padding(.bottom, DesignTokens.blockGap)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text(now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(TypeScale.label)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .monospacedDigit()
            Spacer()
            Text(String(SeededData.patientName.prefix(1)))
                .font(TypeScale.rowTitleCompact)
                .foregroundStyle(DesignTokens.cocoa)
                .frame(width: 34, height: 34)
                .background(DesignTokens.surfaceWarm)
                .clipShape(Circle())
                .accessibilityLabel(SeededData.patientName)
        }
        .frame(height: 36)
    }

    // MARK: Hero

    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignTokens.heroRadius, style: .continuous)
                .fill(DesignTokens.surfaceWarm)
            GeometryReader { geometry in
                ZStack {
                    Circle().fill(Color.white.opacity(0.5))
                        .frame(width: 180, height: 180)
                        .position(x: 20, y: 20)
                    Circle().fill(Color.white.opacity(0.5))
                        .frame(width: 220, height: 220)
                        .position(x: geometry.size.width - 20, y: geometry.size.height)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.heroRadius, style: .continuous))
            .accessibilityHidden(true)

            HStack(alignment: .center, spacing: 0) {
                heroSide(title: "Write", icon: .pencil) { navigation.navigate(to: .journalWrite) }
                    .frame(width: 60)
                Spacer(minLength: DesignTokens.Spacing.small)
                talkButton
                Spacer(minLength: DesignTokens.Spacing.small)
                heroSide(title: "Photo", icon: .camera) { navigation.navigate(to: .journalPhoto) }
                    .frame(width: 60)
            }
            .padding(.horizontal, 22)
            .offset(y: -10)

            VStack {
                Spacer()
                Text("Say it messy. It stays on this phone.")
                    .font(TypeScale.provenance)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .padding(.bottom, DesignTokens.Spacing.compact)
            }
        }
    }

    private var talkButton: some View {
        Button { navigation.navigate(to: .journalVoice) } label: {
            VStack(spacing: 4) {
                AppIcon.microphone.image
                    .font(.system(size: 36, weight: .regular))
                Text("Talk")
                    .font(TypeScale.heroTitle)
                Text("Hold or tap")
                    .font(TypeScale.meta)
                    .opacity(0.92)
            }
            .foregroundStyle(.white)
            .frame(width: 140, height: 140)
            .background(
                Circle()
                    .fill(DesignTokens.orange)
                    .shadow(color: DesignTokens.orangePressed, radius: 0, x: 0, y: 6)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Talk")
        .accessibilityHint("Starts a voice journal")
    }

    private func heroSide(title: String, icon: AppIcon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                icon.image
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(DesignTokens.cocoa)
                    .frame(width: 56, height: 56)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: DesignTokens.cocoa.opacity(0.06), radius: 8, x: 0, y: 2)
                Text(title)
                    .font(TypeScale.metaStrong)
                    .foregroundStyle(DesignTokens.cocoa)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    // MARK: Mood

    private var moodCard: some View {
        Button { navigation.navigate(to: .checkIn) } label: {
            HStack(spacing: DesignTokens.blockGap) {
                MoodMiniBars(values: moodValues)
                Spacer(minLength: DesignTokens.Spacing.small)
                HStack(spacing: 2) {
                    Text("Check in")
                        .font(TypeScale.label)
                    AppIcon.chevronRight.image
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(DesignTokens.cocoa)
            }
            .padding(.horizontal, DesignTokens.Spacing.base)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .background(DesignTokens.surface)
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.v2CardRadius, style: .continuous).stroke(DesignTokens.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.v2CardRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Check in")
        .accessibilityValue(moodAccessibilityValue)
    }

    // MARK: Appointment

    private var appointmentBand: some View {
        HStack(spacing: DesignTokens.blockGap) {
            IconTile(icon: .calendar, size: 42)
                .colorScheme(.dark)
                .background(Color.white.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button {
                if let id = nextAppointment?.id { state.selectAppointment(id: id) }
                navigation.navigate(to: .appointments)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(appointmentHeadline)
                        .font(TypeScale.cardTitle)
                        .foregroundStyle(.white)
                    Text(appointmentDetail)
                        .font(TypeScale.provenance)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(appointmentHeadline). \(appointmentDetail)")
            .accessibilityHint("Opens appointments")
            Button { navigation.navigate(to: nextAppointment?.kind == .tms ? .prepareTMS : .prepareTherapy) } label: {
                Text("Prep")
                    .font(TypeScale.label)
                    .foregroundStyle(DesignTokens.cocoa)
                    .padding(.horizontal, DesignTokens.blockGap)
                    .frame(minHeight: 40)
                    .background(DesignTokens.yellow)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Prepare for the appointment")
        }
        .padding(.horizontal, DesignTokens.Spacing.base)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .background(DesignTokens.cocoa)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.v2CardRadius, style: .continuous))
    }

    // MARK: Up next

    private var upNextCard: some View {
        V2Card(padding: DesignTokens.Spacing.compact) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
                HStack(alignment: .center) {
                    Text("Up next")
                        .font(TypeScale.metaStrong)
                        .foregroundStyle(DesignTokens.cocoaSoft)
                    Spacer()
                    Button { navigation.navigate(to: .goals) } label: {
                        HStack(spacing: 2) {
                            Text(upNextTrailing)
                            AppIcon.chevronRight.image.font(.system(size: 12, weight: .semibold))
                        }
                        .font(TypeScale.metaStrong)
                        .foregroundStyle(DesignTokens.cocoa)
                        .frame(minHeight: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("See all goals")
                }
                if let goal = upNextGoal {
                    HStack(spacing: DesignTokens.Spacing.compact) {
                        Button { Task { _ = await state.transitionGoal(id: goal.id, to: goal.status == .completed ? .active : .completed) } } label: {
                            CompletionCircle(done: goal.status == .completed)
                                .frame(width: DesignTokens.controlMinimum, height: DesignTokens.controlMinimum)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(goal.status == .completed ? "Mark not done" : "Mark done")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(goal.title)
                                .font(TypeScale.rowTitle)
                                .foregroundStyle(DesignTokens.cocoa)
                                .lineLimit(1)
                            ProvenanceInline(voice: goal.provenance.voice, text: "\(goal.provenance.label) · today")
                        }
                    }
                } else {
                    Text("Nothing due today. Add a goal when something matters.")
                        .font(TypeScale.label)
                        .foregroundStyle(DesignTokens.cocoaSoft)
                }
            }
        }
    }

    // MARK: Data

    private var now: Date { state.dependencies.now() }

    private var markedDays: Set<DateComponents> {
        let calendar = Calendar.current
        var days = Set<DateComponents>()
        for entry in state.journals { days.insert(calendar.dateComponents([.year, .month, .day], from: entry.createdAt)) }
        for mood in state.moods { days.insert(calendar.dateComponents([.year, .month, .day], from: mood.createdAt)) }
        for appointment in state.appointments where appointment.status == .completed {
            if let date = appointment.startedAt ?? appointment.scheduledAt {
                days.insert(calendar.dateComponents([.year, .month, .day], from: date))
            }
        }
        return days
    }

    private var moodValues: MoodValues {
        MoodValues(mood: state.mood?.mood, anxiety: state.mood?.anxiety, energy: state.mood?.energy)
    }

    private var moodAccessibilityValue: String {
        guard let mood = state.mood else { return "No check-in yet" }
        return "Anxiety \(mood.anxiety.map(String.init) ?? "not logged"), mood \(mood.mood.map(String.init) ?? "not logged"), energy \(mood.energy.map(String.init) ?? "not logged")"
    }

    private var upNextTrailing: String {
        let goals = "\(openGoals.count) \(openGoals.count == 1 ? "goal" : "goals")"
        let review = state.pendingProgressSuggestions.count
        return review > 0 ? "\(goals) · \(review) to review" : goals
    }

    private var openGoals: [Goal] {
        state.goals.filter { $0.status == .active || $0.status == .proposed }
    }

    private var upNextGoal: Goal? {
        let active = state.goals.filter { $0.status == .active }
        return active.first { $0.cadence == .daily || $0.cadence == .oneOff } ?? active.first
    }

    private var nextAppointment: Appointment? {
        state.appointments.filter { $0.status == .planned }.min {
            ($0.scheduledAt ?? .distantFuture) < ($1.scheduledAt ?? .distantFuture)
        }
    }

    private var appointmentHeadline: String {
        guard let appointment = nextAppointment else { return "No appointment yet" }
        guard let date = appointment.scheduledAt else { return "\(appointment.kind.displayName) scheduled" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now), to: Calendar.current.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<0: return "\(appointment.kind.displayName) was \(-days) \(days == -1 ? "day" : "days") ago"
        case 0: return "\(appointment.kind.displayName) today"
        case 1: return "\(appointment.kind.displayName) tomorrow"
        default: return "\(appointment.kind.displayName) in \(days) days"
        }
    }

    private var appointmentDetail: String {
        guard let appointment = nextAppointment else { return "Add a visit when you are ready" }
        var parts: [String] = []
        if let date = appointment.scheduledAt {
            parts.append(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
        }
        parts.append(appointment.providerName)
        let pinned = state.talkingPoints.filter { $0.status == .open }.count
        parts.append("\(pinned) pinned")
        return parts.joined(separator: " · ")
    }
}
