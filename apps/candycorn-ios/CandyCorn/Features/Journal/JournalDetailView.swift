import SwiftUI

enum JournalDetailTab: String, CaseIterable, Sendable {
    case original = "Original"
    case cleaned = "Cleaned"
    case summary = "Summary"
}

struct JournalDetailView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @State private var selection = JournalDetailTab.original

    private var entry: JournalEntry? {
        SeededData.journalEntries.first { $0.id == SeededData.footballJournalID }
    }

    var body: some View {
        ScreenLayout(
            title: "Football and guilt",
            backAction: navigation.backAction(for: .journalDetail),
            trailing: AnyView(
                Button("More") { navigation.navigate(to: .journalSuggestions) }
                    .font(TypeScale.bodyMedium)
                    .foregroundStyle(DesignTokens.cocoa)
                    .frame(minWidth: DesignTokens.controlMinimum, minHeight: DesignTokens.controlMinimum)
            )
        ) {
            UnderlinePicker(options: JournalDetailTab.allCases, selection: $selection) { $0.rawValue }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                tabContent
                ProvenanceLine(provenance: provenance)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            considerationCard
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selection {
        case .original:
            Text(entry?.rawText ?? "This journal entry is unavailable.")
                .font(TypeScale.body)
                .fixedSize(horizontal: false, vertical: true)
        case .cleaned:
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.base) {
                Text(entry?.cleanedText ?? "No cleaned version is available.")
                    .font(TypeScale.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text("This version organizes your wording. The Original tab remains unchanged.")
                    .font(TypeScale.label)
                    .foregroundStyle(DesignTokens.cocoaSoft)
            }
        case .summary:
            let items = entry?.summaryItems ?? []
            if items.isEmpty {
                Text("No summary is available. Your original is unchanged.")
                    .font(TypeScale.body)
            } else {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.base) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: DesignTokens.Spacing.small) {
                            KernelGlyph(voice: .candyCorn, height: 16)
                                .padding(.top, 3)
                            Text(item)
                                .font(TypeScale.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var provenance: Provenance {
        if selection == .summary {
            return Provenance(
                voice: .candyCorn,
                label: "Candy Corn organized this",
                detail: "Organized from your Sep 5 voice journal.",
                occurredAt: nil,
                sourceRoute: .journalDetail
            )
        }
        return Provenance(
            voice: .user,
            label: selection == .original ? "You said this" : "Your words, organized",
            detail: "Voice journal, Sep 5 at 3:18 PM",
            occurredAt: nil,
            sourceRoute: .journalDetail
        )
    }

    private var considerationCard: some View {
        let point = JournalSuggestionFixtures.guiltPoint
        let added = state.talkingPoints.contains { $0.id == point.id }
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            Text("Something to consider")
                .font(TypeScale.sectionCompact)
            Divider().overlay(DesignTokens.hairline)
            Text("Would you like to bring up why feeling better can create guilt?")
                .font(TypeScale.body)
                .fixedSize(horizontal: false, vertical: true)
            ProvenanceLine(provenance: point.provenance, compact: true)
            Button {
                _ = state.addTalkingPoint(point)
            } label: {
                Label(added ? "Added" : "Add", systemImage: added ? AppIcon.check.rawValue : AppIcon.listPlus.rawValue)
                    .font(TypeScale.bodyMedium)
                    .frame(minHeight: DesignTokens.controlMinimum)
                    .padding(.horizontal, DesignTokens.Spacing.base)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(added ? DesignTokens.sage : DesignTokens.cocoa, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(added ? DesignTokens.sage : DesignTokens.cocoa)
            .disabled(added)
        }
        .padding(DesignTokens.Spacing.base)
        .background(DesignTokens.surfaceWarm)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
    }
}
