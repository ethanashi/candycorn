import SwiftUI

enum HistoryFilter: String, CaseIterable, Hashable, Sendable {
    case all = "All"
    case journal = "Journal"
    case mood = "Mood"
    case therapy = "Therapy"
    case tms = "TMS"
}

struct HistoryDay: Hashable, Sendable {
    let rawValue: String

    static let sep5 = HistoryDay(rawValue: "Sep 5")
    static let sep3 = HistoryDay(rawValue: "Sep 3")
    static let sep2 = HistoryDay(rawValue: "Sep 2")
}

struct HistoryRecord: Identifiable, Equatable, Sendable {
    let id: String
    let day: HistoryDay
    let type: HistoryFilter
    let title: String
    let time: String
    let excerpt: String
    let destination: Route
    let occurredAt: Date
    let entityID: UUID?
    let inputType: JournalEntry.InputType?

    init(
        id: String,
        day: HistoryDay,
        type: HistoryFilter,
        title: String,
        time: String,
        excerpt: String,
        destination: Route,
        occurredAt: Date = .distantPast,
        entityID: UUID? = nil,
        inputType: JournalEntry.InputType? = nil
    ) {
        self.id = id
        self.day = day
        self.type = type
        self.title = title
        self.time = time
        self.excerpt = excerpt
        self.destination = destination
        self.occurredAt = occurredAt
        self.entityID = entityID
        self.inputType = inputType
    }
}

enum HistoryModel {
    static func records(journals: [JournalEntry], moods: [MoodLog], appointments: [Appointment]) -> [HistoryRecord] {
        var records: [HistoryRecord] = []
        for entry in journals.prefix(200) {
            records.append(HistoryRecord(
                id: "journal-\(entry.id)", day: day(for: entry.createdAt), type: .journal,
                title: entry.title, time: entry.createdAt.formatted(date: .omitted, time: .shortened),
                excerpt: journalExcerpt(entry),
                destination: .journalDetail, occurredAt: entry.createdAt, entityID: entry.id, inputType: entry.inputType
            ))
        }
        for mood in moods.prefix(200) {
            records.append(HistoryRecord(
                id: "mood-\(mood.id)", day: day(for: mood.createdAt), type: .mood,
                title: "Mood check-in", time: mood.createdAt.formatted(date: .omitted, time: .shortened),
                excerpt: moodExcerpt(mood), destination: .checkIn,
                occurredAt: mood.createdAt, entityID: mood.id
            ))
        }
        for appointment in appointments.filter({ $0.status == .completed }).prefix(200) {
            let date = appointment.startedAt ?? appointment.scheduledAt ?? .distantPast
            let minutes = appointment.endedAt.flatMap { end in appointment.startedAt.map { Int(end.timeIntervalSince($0) / 60) } }
            var parts: [String] = []
            if let minutes, minutes > 0 { parts.append("\(minutes) min") }
            parts.append(appointment.transcriptID != nil ? "transcript ready" : (appointment.recordingAttachmentID != nil ? "recording saved" : "notes"))
            records.append(HistoryRecord(
                id: "appointment-\(appointment.id)", day: day(for: date),
                type: appointment.kind == .tms ? .tms : .therapy,
                title: "\(appointment.kind.displayName) with \(appointment.providerName)",
                time: date.formatted(date: .omitted, time: .shortened),
                excerpt: parts.joined(separator: " · "),
                destination: appointment.kind == .tms ? .tmsPost : .therapySession,
                occurredAt: date, entityID: appointment.id
            ))
        }
        return records.sorted { $0.occurredAt > $1.occurredAt }
    }

    static func records(mood: MoodLog?) -> [HistoryRecord] {
        var records = fixedRecords
        if let mood, mood.mood != nil || mood.anxiety != nil || mood.energy != nil {
            records.insert(
                HistoryRecord(
                    id: "mood-sep-5",
                    day: .sep5,
                    type: .mood,
                    title: "Mood check-in",
                    time: "5:30 PM",
                    excerpt: mood.note ?? "Mood, anxiety, and energy saved.",
                    destination: .checkIn
                ),
                at: 2
            )
        }
        return records
    }

    static func filteredRecords(_ records: [HistoryRecord], by filter: HistoryFilter) -> [HistoryRecord] {
        guard filter != .all else { return records }
        return records.filter { $0.type == filter }
    }

    private static func journalExcerpt(_ entry: JournalEntry) -> String {
        switch entry.inputType {
        case .voice: "Voice journal"
        case .text: "Written"
        case .photo: "Photographed page"
        }
    }

    private static func moodExcerpt(_ mood: MoodLog) -> String {
        var parts: [String] = []
        if let value = mood.anxiety { parts.append("Anxiety \(value)") }
        if let value = mood.mood { parts.append("Mood \(value)") }
        if let value = mood.energy { parts.append("Energy \(value)") }
        return parts.isEmpty ? (mood.note ?? "Saved") : parts.joined(separator: " · ")
    }

    private static let fixedRecords = [
        HistoryRecord(id: "journal-football", day: .sep5, type: .journal, title: "Football and feeling guilty", time: "3:18 PM", excerpt: "Exercise helped, then feeling better brought up guilt.", destination: .journalDetail),
        HistoryRecord(id: "tms-post", day: .sep5, type: .tms, title: "TMS post-session note", time: "9:52 AM", excerpt: "Saved observations without claiming what caused the change.", destination: .tmsPost),
        HistoryRecord(id: "journal-timeline", day: .sep3, type: .journal, title: "The senior-year timeline", time: "4:06 PM", excerpt: "The missed chance to prove I could have played still feels unresolved.", destination: .journalDetail),
        HistoryRecord(id: "therapy-session", day: .sep2, type: .therapy, title: "Therapy with Dr. Elena Park", time: "2:00 PM", excerpt: "Worked on the senior-year story and moving-forward guilt.", destination: .therapySession),
    ]

    private static func day(for date: Date) -> HistoryDay {
        HistoryDay(rawValue: date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
    }
}

/// History tab (v2): everything in the order it happened, filters by kind, day headers carry the day's mood.
struct HistoryView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @State private var filter: HistoryFilter = .all
    @State private var pendingSend: PendingAISend?
    @State private var sendTask: Task<Void, Never>?
    @State private var isPreparingWeekly = false
    @State private var weeklyNotice: String?

    private var allRecords: [HistoryRecord] {
        HistoryModel.records(journals: state.journals, moods: state.moods, appointments: state.appointments)
    }

    private var visibleRecords: [HistoryRecord] {
        HistoryModel.filteredRecords(allRecords, by: filter)
    }

    private var visibleDays: [HistoryDay] {
        visibleRecords.reduce(into: []) { days, record in
            if !days.contains(record.day) { days.append(record.day) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.blockGap) {
                V2TitleRow(
                    title: "History",
                    trailing: AnyView(RoundActionButton(icon: .search, label: "Search your history") {
                        navigation.navigate(to: .search)
                    })
                )
                filterBar
                if filter == .all {
                    weeklyBlock
                }
                if visibleRecords.isEmpty {
                    emptyState
                } else {
                    ForEach(visibleDays, id: \.self) { day in
                        let records = visibleRecords.filter { $0.day == day }
                        dayHeader(day, records: records)
                        VStack(spacing: 0) {
                            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                                if index > 0 { Rectangle().fill(DesignTokens.hairline).frame(height: 1) }
                                HistoryRow(record: record) { open(record) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, DesignTokens.screenInset)
            .padding(.top, DesignTokens.Spacing.small)
            .padding(.bottom, DesignTokens.tabBarClearance)
        }
        .background(DesignTokens.canvas.ignoresSafeArea())
        .sheet(item: $pendingSend, onDismiss: cancelSend) { pending in
            WhatLeavesDeviceSheet(
                pending: pending,
                processingState: state.aiProcessingState(for: pending.action),
                onSend: { send(pending) },
                onCancel: cancelSend
            )
        }
        .onDisappear(perform: cancelSend)
    }

    // MARK: Weekly summary (Phase 5)

    @ViewBuilder private var weeklyBlock: some View {
        if let summary = state.currentWeeklySummary {
            WeeklySummaryCard(summary: summary)
        } else if weeklyAvailable {
            V2GroupCard {
                V2ListRow(
                    icon: .sparkles,
                    title: isPreparingWeekly ? "Preparing" : "Summarize this week",
                    detail: "Mood trend, what got done, what kept coming up. You review what leaves first.",
                    divider: false,
                    disabled: isPreparingWeekly
                ) { prepareWeekly() }
            }
        } else {
            V2GroupCard {
                V2ListRow(
                    icon: .sparkles,
                    title: "Weekly summary is off",
                    detail: "Turn on Organizer to summarize your week from your own entries.",
                    value: "Settings",
                    divider: false
                ) { navigation.openSettings(.ai) }
            }
        }
        if let weeklyNotice {
            StatusNotice(title: "No weekly summary yet", detail: weeklyNotice, kind: .information)
        }
    }

    private var weeklyAvailable: Bool {
        state.aiMode != .off && state.aiProvider == .router && state.hasOpenRouterKey && state.routerAvailable
    }

    private func prepareWeekly() {
        guard !isPreparingWeekly, pendingSend == nil else { return }
        isPreparingWeekly = true
        weeklyNotice = nil
        Task {
            defer { isPreparingWeekly = false }
            do {
                if let pending = try await state.refreshWeeklySummary() {
                    pendingSend = pending
                } else if state.currentWeeklySummary == nil {
                    weeklyNotice = "Not enough saved this week to summarize yet. Journals, check-ins, and sessions count."
                }
            } catch let error as UserFacingError {
                weeklyNotice = error.message
            } catch {
                weeklyNotice = "This week could not be prepared. Your entries are unchanged."
            }
        }
    }

    private func send(_ pending: PendingAISend) {
        guard sendTask == nil else { return }
        if case .failed = state.aiProcessingState(for: pending.action) {
            pendingSend = nil
            prepareWeekly()
            return
        }
        sendTask = Task {
            let succeeded = await state.performAISend(pending)
            guard !Task.isCancelled, pendingSend?.id == pending.id else {
                sendTask = nil
                return
            }
            sendTask = nil
            if succeeded {
                pendingSend = nil
            } else if case let .failed(message) = state.aiProcessingState(for: pending.action) {
                weeklyNotice = message
            }
        }
    }

    private func cancelSend() {
        sendTask?.cancel()
        sendTask = nil
        pendingSend = nil
    }

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: DesignTokens.Spacing.small) {
                ForEach(HistoryFilter.allCases, id: \.self) { option in
                    Button(option.rawValue) { filter = option }
                        .font(TypeScale.label)
                        .foregroundStyle(filter == option ? Color.white : DesignTokens.cocoa)
                        .padding(.horizontal, DesignTokens.Spacing.compact)
                        .frame(minHeight: 34)
                        .background(filter == option ? DesignTokens.cocoa : DesignTokens.surface)
                        .overlay(Capsule().stroke(filter == option ? DesignTokens.cocoa : DesignTokens.hairline, lineWidth: 1))
                        .clipShape(Capsule())
                        .accessibilityAddTraits(filter == option ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Filter history")
    }

    private func dayHeader(_ day: HistoryDay, records: [HistoryRecord]) -> some View {
        let mood = records.compactMap { record -> MoodLog? in
            guard record.type == .mood, let id = record.entityID else { return nil }
            return state.moods.first { $0.id == id }
        }.first
        return HStack {
            Text(day.rawValue)
                .font(TypeScale.metaStrong)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .monospacedDigit()
            Spacer()
            if let mood {
                MoodMiniBars(values: MoodValues(mood: mood.mood, anxiety: mood.anxiety, energy: mood.energy), barWidth: 22, showsLabels: false)
            }
        }
        .frame(height: 22)
        .padding(.top, DesignTokens.Spacing.xSmall)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        V2Card(background: DesignTokens.surfaceWarm, showsBorder: false) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                Text("No \(filter.rawValue.lowercased()) entries yet")
                    .font(TypeScale.cardTitle)
                    .foregroundStyle(DesignTokens.cocoa)
                Text("Your other history is still here. Choose a different filter.")
                    .font(TypeScale.label)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func open(_ record: HistoryRecord) {
        if record.type == .journal, let id = record.entityID {
            state.selectJournal(id: id)
        } else if record.type == .therapy || record.type == .tms, let id = record.entityID {
            state.selectAppointment(id: id)
        }
        navigation.navigate(to: record.destination)
    }
}

private struct HistoryRow: View {
    let record: HistoryRecord
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: DesignTokens.Spacing.compact) {
                IconTile(icon: icon, size: 40, dark: record.type == .therapy || record.type == .tms)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.title)
                        .font(TypeScale.rowTitleCompact)
                        .foregroundStyle(DesignTokens.cocoa)
                        .lineLimit(1)
                    Text(record.excerpt)
                        .font(TypeScale.meta)
                        .foregroundStyle(DesignTokens.cocoaSoft)
                        .lineLimit(1)
                }
                Spacer(minLength: DesignTokens.Spacing.small)
                Text(record.time)
                    .font(TypeScale.meta)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .monospacedDigit()
            }
            .padding(.vertical, DesignTokens.Spacing.small)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(record.title), \(record.excerpt), \(record.time)")
        .accessibilityHint("Opens this entry")
    }

    private var icon: AppIcon {
        switch record.type {
        case .all: .clock
        case .journal:
            switch record.inputType {
            case .voice: .microphone
            case .photo: .camera
            case .text, .none: .pencil
            }
        case .mood: .heart
        case .therapy: .calendar
        case .tms: .bolt
        }
    }
}

/// The week in review: four short sections, every line traced to your own entries.
private struct WeeklySummaryCard: View {
    let summary: WeeklySummaryResult

    var body: some View {
        V2Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: DesignTokens.Spacing.compact) {
                    IconTile(icon: .sparkles, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This week")
                            .font(TypeScale.cardTitle)
                            .foregroundStyle(DesignTokens.cocoa)
                        Text(intervalText)
                            .font(TypeScale.meta)
                            .foregroundStyle(DesignTokens.cocoaSoft)
                    }
                    Spacer(minLength: 0)
                }
                .padding(DesignTokens.Spacing.base)
                ForEach(summary.sections.filter { !$0.items.isEmpty }) { section in
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        Text(Self.title(for: section.kind))
                            .font(TypeScale.metaStrong)
                            .foregroundStyle(DesignTokens.cocoaSoft)
                        ForEach(section.items) { item in
                            HStack(alignment: .top, spacing: DesignTokens.Spacing.small) {
                                KernelGlyph(voice: item.provenance, height: 12, decorative: true)
                                    .padding(.top, 4)
                                Text(item.text)
                                    .font(TypeScale.label)
                                    .foregroundStyle(DesignTokens.cocoa)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.base)
                    .padding(.vertical, DesignTokens.Spacing.compact)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) {
                        Rectangle().fill(DesignTokens.hairline).frame(height: 1).padding(.horizontal, DesignTokens.Spacing.base)
                    }
                }
                ProvenanceStack(provenance: Provenance(
                    voice: .candyCorn,
                    label: "Candy Corn summarized your week",
                    detail: "\(summary.metadata.provider), \(summary.metadata.model). Every line points at something you saved.",
                    occurredAt: summary.interval.end,
                    sourceRoute: nil
                ))
                .padding(.horizontal, DesignTokens.Spacing.base)
                .padding(.vertical, DesignTokens.Spacing.compact)
            }
        }
    }

    private var intervalText: String {
        let end = summary.interval.end.addingTimeInterval(-1)
        return "\(summary.interval.start.formatted(.dateTime.month(.abbreviated).day())) to \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    static func title(for kind: WeeklySummarySectionKind) -> String {
        switch kind {
        case .moodTrend: "Mood this week"
        case .completedWork: "What got done"
        case .recurringTopics: "What kept coming up"
        case .openForNextAppointment: "Open for your next appointment"
        }
    }
}
