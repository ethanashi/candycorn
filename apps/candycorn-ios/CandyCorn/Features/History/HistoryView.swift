import SwiftUI

enum HistoryFilter: String, CaseIterable, Hashable, Sendable {
    case all = "All"
    case journal = "Journal"
    case mood = "Mood"
    case therapy = "Therapy"
    case tms = "TMS"
}

enum HistoryDay: String, CaseIterable, Hashable, Sendable {
    case sep5 = "Sep 5"
    case sep3 = "Sep 3"
    case sep2 = "Sep 2"
}

struct HistoryRecord: Identifiable, Equatable, Sendable {
    let id: String
    let day: HistoryDay
    let type: HistoryFilter
    let title: String
    let time: String
    let excerpt: String
    let destination: Route
}

enum HistoryModel {
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

    private static let fixedRecords = [
        HistoryRecord(
            id: "journal-football",
            day: .sep5,
            type: .journal,
            title: "Football and feeling guilty",
            time: "3:18 PM",
            excerpt: "Exercise helped, then feeling better brought up guilt.",
            destination: .journalDetail
        ),
        HistoryRecord(
            id: "tms-post",
            day: .sep5,
            type: .tms,
            title: "TMS post-session note",
            time: "9:52 AM",
            excerpt: "Saved observations without claiming what caused the change.",
            destination: .tmsPost
        ),
        HistoryRecord(
            id: "journal-timeline",
            day: .sep3,
            type: .journal,
            title: "The senior-year timeline",
            time: "4:06 PM",
            excerpt: "The missed chance to prove I could have played still feels unresolved.",
            destination: .journalDetail
        ),
        HistoryRecord(
            id: "therapy-session",
            day: .sep2,
            type: .therapy,
            title: "Therapy with Dr. Elena Park",
            time: "2:00 PM",
            excerpt: "Worked on the senior-year story and moving-forward guilt.",
            destination: .therapySession
        ),
    ]
}

struct HistoryView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var filter: HistoryFilter = .all

    private var visibleRecords: [HistoryRecord] {
        HistoryModel.filteredRecords(HistoryModel.records(mood: state.mood), by: filter)
    }

    var body: some View {
        ScreenLayout(title: "History", subtitle: "Your care thread, in the order it happened.") {
            filterBar
            if visibleRecords.isEmpty {
                emptyState
            } else {
                LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.xLarge) {
                    ForEach(HistoryDay.allCases, id: \.self) { day in
                        let records = visibleRecords.filter { $0.day == day }
                        if !records.isEmpty {
                            HistoryDaySection(
                                day: day,
                                records: records,
                                mood: state.mood,
                                usesVerticalHeader: dynamicTypeSize.isAccessibilitySize,
                                onOpen: navigation.navigate
                            )
                        }
                    }
                }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: DesignTokens.Spacing.small) {
                ForEach(HistoryFilter.allCases, id: \.self) { option in
                    Button(option.rawValue) { filter = option }
                        .font(TypeScale.provenance)
                        .foregroundStyle(filter == option ? Color.white : DesignTokens.cocoaSoft)
                        .padding(.horizontal, DesignTokens.Spacing.compact)
                        .frame(minHeight: DesignTokens.controlMinimum)
                        .background(filter == option ? DesignTokens.orange : DesignTokens.surface)
                        .overlay(
                            Capsule().stroke(filter == option ? DesignTokens.orange : DesignTokens.hairline, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                        .accessibilityAddTraits(filter == option ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Filter history")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            KernelGlyph(voice: .candyCorn, height: 20, decorative: true)
            Text("No \(filter.rawValue.lowercased()) entries yet")
                .font(TypeScale.sectionCompact)
                .foregroundStyle(DesignTokens.cocoa)
            Text("Your other history is still here. Choose a different filter.")
                .font(TypeScale.label)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, DesignTokens.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider().overlay(DesignTokens.hairline) }
        .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
    }
}

private struct HistoryDaySection: View {
    let day: HistoryDay
    let records: [HistoryRecord]
    let mood: MoodLog?
    let usesVerticalHeader: Bool
    let onOpen: (Route) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if usesVerticalHeader {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                    dayTitle
                    moodBands.frame(maxWidth: 220)
                }
            } else {
                HStack(spacing: DesignTokens.Spacing.base) {
                    dayTitle
                    Spacer(minLength: DesignTokens.Spacing.small)
                    moodBands.frame(width: 136)
                }
            }
            ForEach(records) { record in
                HistoryRow(record: record) { onOpen(record.destination) }
            }
        }
    }

    private var dayTitle: some View {
        Text(day.rawValue)
            .font(TypeScale.sectionCompact)
            .foregroundStyle(DesignTokens.cocoa)
            .monospacedDigit()
    }

    private var moodBands: some View {
        MoodBands(
            values: MoodValues(mood: mood?.mood, anxiety: mood?.anxiety, energy: mood?.energy),
            compact: true
        )
        .dynamicTypeSize(.small ... .large)
    }
}

private struct HistoryRow: View {
    let record: HistoryRecord
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: DesignTokens.Spacing.small) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
                    HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.small) {
                        Text(record.title)
                            .font(TypeScale.bodyMedium)
                            .foregroundStyle(DesignTokens.cocoa)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(record.time)
                            .font(TypeScale.provenance)
                            .foregroundStyle(DesignTokens.cocoaSoft)
                            .monospacedDigit()
                    }
                    Text(record.type.rawValue)
                        .font(TypeScale.provenance)
                        .foregroundStyle(DesignTokens.orangePressed)
                    Text(record.excerpt)
                        .font(TypeScale.provenance)
                        .foregroundStyle(DesignTokens.cocoaSoft)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                AppIcon.chevronRight.image
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DesignTokens.cocoaSoft)
            }
            .padding(.vertical, DesignTokens.Spacing.base)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Divider().overlay(DesignTokens.hairline) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(record.title), \(record.type.rawValue), \(record.time). \(record.excerpt)")
        .accessibilityHint("Opens this history entry")
    }
}
