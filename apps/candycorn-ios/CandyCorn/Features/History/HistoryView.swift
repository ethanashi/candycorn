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
            .padding(.bottom, DesignTokens.Spacing.large)
        }
        .background(DesignTokens.canvas.ignoresSafeArea())
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
