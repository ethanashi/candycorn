import SwiftUI

// Shared building blocks for the v2 front end (docs/design/v2). Every screen's first
// viewport ends on the tab bar with a constant 14 point gap between blocks.

extension DesignTokens {
    /// Inactive tab bar glyph and label color.
    static let tabInactive = Color(hex: "#8F867E")
    /// Constant vertical rhythm between blocks on a screen.
    static let blockGap: CGFloat = 14
    /// Radius for the large hero panel on Today.
    static let heroRadius: CGFloat = 30
    /// Radius for the standard v2 card.
    static let v2CardRadius: CGFloat = 22
}

extension TypeScale {
    static let tabLabel = Font.custom("AvenirNext-Medium", size: 11, relativeTo: .caption2)
    static let cardTitle = Font.custom("AvenirNext-DemiBold", size: 17, relativeTo: .headline)
    static let rowTitle = Font.custom("AvenirNext-DemiBold", size: 16, relativeTo: .body)
    static let rowTitleCompact = Font.custom("AvenirNext-DemiBold", size: 15, relativeTo: .subheadline)
    static let meta = Font.custom("AvenirNext-Medium", size: 12, relativeTo: .caption)
    static let metaStrong = Font.custom("AvenirNext-DemiBold", size: 12, relativeTo: .caption)
    static let numeral = Font.custom("AvenirNext-DemiBold", size: 17, relativeTo: .headline).monospacedDigit()
    static let heroTitle = Font.custom("AvenirNext-Bold", size: 19, relativeTo: .headline)
    static let screenTitle = Font.custom("AvenirNext-Bold", size: 30, relativeTo: .largeTitle)
}

/// A white card with a hairline border and the v2 radius.
struct V2Card<Content: View>: View {
    var padding: CGFloat = DesignTokens.Spacing.base
    var background: Color = DesignTokens.surface
    var showsBorder = true
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .overlay {
                if showsBorder {
                    RoundedRectangle(cornerRadius: DesignTokens.v2CardRadius, style: .continuous)
                        .stroke(DesignTokens.hairline, lineWidth: 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.v2CardRadius, style: .continuous))
    }
}

/// Screen title row: large title at left, one round action at right.
struct V2TitleRow: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(TypeScale.screenTitle)
                .foregroundStyle(DesignTokens.cocoa)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DesignTokens.Spacing.small)
            trailing
        }
        .frame(minHeight: DesignTokens.controlMinimum)
    }
}

/// A 40 point round action button used in title rows.
struct RoundActionButton: View {
    let icon: AppIcon
    let label: String
    var dark = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            icon.image
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(dark ? Color.white : DesignTokens.cocoa)
                .frame(width: 40, height: 40)
                .background(dark ? DesignTokens.cocoa : DesignTokens.surfaceWarm)
                .clipShape(Circle())
                .frame(width: DesignTokens.controlMinimum, height: DesignTokens.controlMinimum)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Icon in a warm rounded tile, used at the left of rows and cards.
struct IconTile: View {
    let icon: AppIcon
    var size: CGFloat = 40
    var dark = false

    var body: some View {
        icon.image
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(dark ? Color.white : DesignTokens.cocoa)
            .frame(width: size, height: size)
            .background(dark ? DesignTokens.cocoa : DesignTokens.surfaceWarm)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.33, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Three small horizontal bars for anxiety, mood, energy. Used on day headers and the Today mood card.
struct MoodMiniBars: View {
    let values: MoodValues
    var barWidth: CGFloat = 34
    var showsLabels = true

    var body: some View {
        HStack(spacing: showsLabels ? DesignTokens.blockGap : 5) {
            bar(.anxiety, color: DesignTokens.yellow)
            bar(.mood, color: DesignTokens.orange)
            bar(.energy, color: DesignTokens.cocoa)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func bar(_ dimension: MoodDimension, color: Color) -> some View {
        let value = values.value(for: dimension)
        return VStack(spacing: 4) {
            ZStack(alignment: .leading) {
                Capsule().fill(DesignTokens.hairline)
                Capsule().fill(color)
                    .frame(width: barWidth * CGFloat(value ?? 0) / 10)
            }
            .frame(width: barWidth, height: showsLabels ? 8 : 6)
            if showsLabels {
                Text(value.map(String.init) ?? "–")
                    .font(TypeScale.numeral)
                    .foregroundStyle(DesignTokens.cocoa)
                Text(dimension.title)
                    .font(TypeScale.tabLabel)
                    .foregroundStyle(DesignTokens.cocoaSoft)
            }
        }
    }

    private var accessibilityText: String {
        "Anxiety \(values.anxiety.map(String.init) ?? "not logged"), mood \(values.mood.map(String.init) ?? "not logged"), energy \(values.energy.map(String.init) ?? "not logged")"
    }
}

/// Seven days ending today; a dot marks days with an entry.
struct WeekStrip: View {
    let today: Date
    let markedDays: Set<DateComponents>
    var calendar: Calendar = .current

    var body: some View {
        HStack {
            ForEach(days, id: \.self) { day in
                let isToday = calendar.isDate(day, inSameDayAs: today)
                let components = calendar.dateComponents([.year, .month, .day], from: day)
                VStack(spacing: 5) {
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(TypeScale.tabLabel)
                        .foregroundStyle(DesignTokens.cocoaSoft)
                    Text(day.formatted(.dateTime.day()))
                        .font(TypeScale.rowTitleCompact)
                        .monospacedDigit()
                        .foregroundStyle(isToday ? Color.white : DesignTokens.cocoa)
                        .frame(width: 32, height: 32)
                        .background(isToday ? DesignTokens.cocoa : Color.clear)
                        .clipShape(Circle())
                    Circle()
                        .fill(markedDays.contains(components) ? DesignTokens.orange : DesignTokens.hairline)
                        .frame(width: 6, height: 6)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide).day()))\(isToday ? ", today" : "")\(markedDays.contains(components) ? ", has entries" : "")")
            }
        }
    }

    private var days: [Date] {
        (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: today)) }
    }
}

/// A row header line used above cards: title left, quiet trailing text right.
struct SectionLine: View {
    let title: String
    var trailing: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(TypeScale.rowTitleCompact)
                .foregroundStyle(DesignTokens.cocoa)
            Spacer(minLength: DesignTokens.Spacing.small)
            if let trailing {
                if let action {
                    Button(action: action) {
                        HStack(spacing: 2) {
                            Text(trailing)
                            AppIcon.chevronRight.image.font(.system(size: 12, weight: .semibold))
                        }
                        .font(TypeScale.meta)
                        .foregroundStyle(DesignTokens.cocoaSoft)
                        .frame(minHeight: DesignTokens.controlMinimum)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(trailing)
                        .font(TypeScale.meta)
                        .foregroundStyle(DesignTokens.cocoaSoft)
                }
            }
        }
        .frame(minHeight: 22)
    }
}

/// Compact provenance: kernel glyph plus one short sentence-case line.
struct ProvenanceInline: View {
    let voice: ProvenanceVoice
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            KernelGlyph(voice: voice, height: 12, decorative: true)
            Text(text)
                .font(TypeScale.meta)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Round completion control used on goal rows.
struct CompletionCircle: View {
    let done: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(done ? DesignTokens.sage : DesignTokens.surface)
            Circle()
                .stroke(done ? DesignTokens.sage : Color(hex: "#D9D0C7"), lineWidth: 2)
            if done {
                AppIcon.check.image
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 26, height: 26)
    }
}

extension Provenance {
    /// One-line provenance in the v2 voice: "You chose this · Sep 3".
    var inlineText: String {
        if let occurredAt {
            return "\(label) · \(occurredAt.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return label
    }
}
