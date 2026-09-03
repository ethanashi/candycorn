import SwiftUI

/// Journal tab root (v2): entries newest first, grouped by day with the day's mood beside the date.
struct JournalListView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.blockGap) {
                    V2TitleRow(
                        title: "Journal",
                        trailing: AnyView(RoundActionButton(icon: .search, label: "Search your journal") {
                            navigation.navigate(to: .search)
                        })
                    )
                    if groups.isEmpty {
                        emptyState
                    }
                    ForEach(groups) { group in
                        dayHeader(group)
                        ForEach(group.entries) { entry in
                            JournalEntryCard(entry: entry, meta: meta(for: entry)) {
                                state.selectJournal(id: entry.id)
                                navigation.navigate(to: .journalDetail)
                            }
                        }
                    }
                }
                .padding(.horizontal, DesignTokens.screenInset)
                .padding(.top, DesignTokens.Spacing.small)
                .padding(.bottom, 96)
            }
            Button { navigation.navigate(to: .journalVoice) } label: {
                AppIcon.microphone.image
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(DesignTokens.orange).shadow(color: DesignTokens.orangePressed, radius: 0, x: 0, y: 6))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 22)
            .padding(.bottom, DesignTokens.Spacing.compact)
            .accessibilityLabel("Talk")
            .accessibilityHint("Starts a voice journal")
        }
        .background(DesignTokens.canvas.ignoresSafeArea())
    }

    private func dayHeader(_ group: JournalDayGroup) -> some View {
        HStack {
            Text(group.title)
                .font(TypeScale.metaStrong)
                .foregroundStyle(DesignTokens.cocoaSoft)
            Spacer()
            if let mood = group.mood {
                MoodMiniBars(values: MoodValues(mood: mood.mood, anxiety: mood.anxiety, energy: mood.energy), barWidth: 22, showsLabels: false)
            }
        }
        .frame(height: 22)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        V2Card(background: DesignTokens.surfaceWarm, showsBorder: false) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                Text("Nothing here yet")
                    .font(TypeScale.cardTitle)
                    .foregroundStyle(DesignTokens.cocoa)
                Text("Talk, write, or photograph a page. Everything stays on this phone.")
                    .font(TypeScale.label)
                    .foregroundStyle(DesignTokens.cocoaSoft)
            }
        }
    }

    private var groups: [JournalDayGroup] {
        JournalDayGroup.build(journals: state.journals, moods: state.moods, now: state.dependencies.now())
    }

    private func meta(for entry: JournalEntry) -> [JournalCardMeta] {
        var items: [JournalCardMeta] = []
        let suggestions = state.artifacts.filter { $0.kind == .journalSignals && $0.sourceIDs.contains(entry.id) }.count
        if suggestions > 0 { items.append(JournalCardMeta(voice: .candyCorn, text: "\(suggestions) \(suggestions == 1 ? "suggestion" : "suggestions")")) }
        if entry.cleanedText != nil { items.append(JournalCardMeta(voice: nil, text: "Cleaned")) }
        if entry.inputType == .photo, entry.cleanedText != nil || !entry.rawText.isEmpty { items.append(JournalCardMeta(voice: .candyCorn, text: "Text extracted")) }
        if entry.pinnedForNextAppointment { items.append(JournalCardMeta(voice: .user, text: "Pinned")) }
        if items.isEmpty { items.append(JournalCardMeta(voice: .user, text: entry.provenance.label)) }
        return Array(items.prefix(3))
    }
}

struct JournalDayGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let entries: [JournalEntry]
    let mood: MoodLog?

    static func build(journals: [JournalEntry], moods: [MoodLog], now: Date, calendar: Calendar = .current) -> [JournalDayGroup] {
        let sorted = journals.sorted { $0.createdAt > $1.createdAt }
        var order: [Date] = []
        var buckets: [Date: [JournalEntry]] = [:]
        for entry in sorted {
            let day = calendar.startOfDay(for: entry.createdAt)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(entry)
        }
        return order.map { day in
            let mood = moods.filter { calendar.isDate($0.createdAt, inSameDayAs: day) }.max { $0.createdAt < $1.createdAt }
            return JournalDayGroup(id: day.formatted(.iso8601), title: title(for: day, now: now, calendar: calendar), entries: buckets[day] ?? [], mood: mood)
        }
    }

    static func title(for day: Date, now: Date, calendar: Calendar) -> String {
        let dateText = day.formatted(.dateTime.month(.abbreviated).day())
        if calendar.isDate(day, inSameDayAs: now) { return "Today, \(dateText)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) { return "Yesterday, \(dateText)" }
        return "\(day.formatted(.dateTime.weekday(.wide))), \(dateText)"
    }
}

struct JournalCardMeta: Equatable {
    let voice: ProvenanceVoice?
    let text: String
}

private struct JournalEntryCard: View {
    let entry: JournalEntry
    let meta: [JournalCardMeta]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.compact) {
                IconTile(icon: icon, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.title)
                            .font(TypeScale.rowTitle)
                            .foregroundStyle(DesignTokens.cocoa)
                            .lineLimit(1)
                        Spacer(minLength: DesignTokens.Spacing.small)
                        Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                            .font(TypeScale.meta)
                            .foregroundStyle(DesignTokens.cocoaSoft)
                            .monospacedDigit()
                    }
                    if !excerpt.isEmpty {
                        Text(excerpt)
                            .font(TypeScale.label)
                            .foregroundStyle(DesignTokens.cocoaSoft)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    HStack(spacing: DesignTokens.Spacing.small) {
                        ForEach(Array(meta.enumerated()), id: \.offset) { index, item in
                            if index > 0 {
                                Circle().fill(Color(hex: "#C9C0B8")).frame(width: 4, height: 4)
                            }
                            HStack(spacing: 5) {
                                if let voice = item.voice { KernelGlyph(voice: voice, height: 12, decorative: true) }
                                Text(item.text)
                                    .font(TypeScale.metaStrong)
                                    .foregroundStyle(DesignTokens.cocoa)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(DesignTokens.Spacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.surface)
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.v2CardRadius, style: .continuous).stroke(DesignTokens.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.v2CardRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.title), \(entry.createdAt.formatted(date: .omitted, time: .shortened)). \(excerpt)")
        .accessibilityHint("Opens this journal entry")
    }

    private var icon: AppIcon {
        switch entry.inputType {
        case .voice: .microphone
        case .text: .pencil
        case .photo: .camera
        }
    }

    private var excerpt: String {
        let text = entry.cleanedText ?? entry.rawText
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
