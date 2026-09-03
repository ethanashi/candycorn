import Foundation
import SwiftUI

struct MemorySearchRecord: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let excerpt: String
    let searchableText: String
    let destination: Route
    let provenance: Provenance
}

enum MemorySearchModel {
    static let maximumQueryLength = 120

    static func records(goals: [Goal], talkingPoints: [TalkingPoint]) -> [MemorySearchRecord] {
        let goalRecords = goals.prefix(200).map { goal in
            MemorySearchRecord(
                id: "goal-\(goal.id.uuidString)",
                title: goal.title,
                excerpt: GoalLedgerCadence.allCases.first(where: { $0.includes(goal) })?.rawValue ?? "Goal",
                searchableText: "\(goal.title) \(goal.provenance.label) \(goal.provenance.detail)",
                destination: .goals,
                provenance: goal.provenance
            )
        }
        let pointRecords = talkingPoints.prefix(200).map { point in
            let relatedTerms = point.id == SeededData.talkingPoints.first?.id ? "football senior year" : ""
            return MemorySearchRecord(
                id: "point-\(point.id.uuidString)",
                title: point.text,
                excerpt: BringUpLogic.targetLabel(for: point),
                searchableText: "\(point.text) \(relatedTerms) \(point.provenance.label) \(point.provenance.detail)",
                destination: .bringUp,
                provenance: point.provenance
            )
        }
        return fixedRecords + goalRecords + pointRecords
    }

    static func results(for query: String, in records: [MemorySearchRecord]) -> [MemorySearchRecord] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }
        return records.filter { record in
            normalize("\(record.title) \(record.excerpt) \(record.searchableText)").contains(normalizedQuery)
        }
    }

    static func boundedQuery(_ value: String) -> String {
        String(value.prefix(maximumQueryLength))
    }

    static func trimmedQuery(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalize(_ value: String) -> String {
        trimmedQuery(value).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static let fixedRecords = [
        MemorySearchRecord(
            id: "search-journal-football",
            title: "Football and feeling guilty",
            excerpt: "Exercise helped, then feeling better brought up guilt.",
            searchableText: "football guilt exercise feeling better journal",
            destination: .journalDetail,
            provenance: Provenance(
                voice: .user,
                label: "You said this",
                detail: "Journal, Sep 5 at 3:18 PM",
                occurredAt: Date(timeIntervalSince1970: 1_788_646_680),
                sourceRoute: .journalDetail
            )
        ),
        MemorySearchRecord(
            id: "search-therapy-football",
            title: "Senior-year football in therapy",
            excerpt: "Not getting the chance to prove you could have played still hurts.",
            searchableText: "football senior year prove played therapy coaches",
            destination: .therapySession,
            provenance: Provenance(
                voice: .provider,
                label: "Dr. Elena Park reflected this",
                detail: "Therapy, Sep 2 at 12:48",
                occurredAt: Date(timeIntervalSince1970: 1_788_383_568),
                sourceRoute: .therapySession
            )
        ),
    ]
}

struct SearchMemoryView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @State private var query = ""

    private var trimmedQuery: String {
        MemorySearchModel.trimmedQuery(query)
    }

    private var results: [MemorySearchRecord] {
        state.searchResults.map { hit in
            MemorySearchRecord(
                id: hit.id,
                title: hit.title,
                excerpt: hit.excerpt,
                searchableText: hit.excerpt,
                destination: destination(for: hit.kind),
                provenance: Provenance(voice: .user, label: "Saved on this device", detail: hit.occurredAt.formatted(date: .abbreviated, time: .shortened), occurredAt: hit.occurredAt, sourceRoute: destination(for: hit.kind))
            )
        }
    }

    var body: some View {
        ScreenLayout(
            title: "Search memory",
            subtitle: "Search across journals, sessions, goals, and pinned items.",
            backAction: navigation.backAction(for: .search)
        ) {
            searchField
            if trimmedQuery.isEmpty {
                prompt
            } else {
                searchResponse
            }
        }
        .task(id: query) {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard !Task.isCancelled else { return }
            await state.search(query)
        }
    }

    @ViewBuilder private var searchResponse: some View {
        switch state.searchState {
        case .loading:
            HStack(spacing: DesignTokens.Spacing.small) {
                ProgressView()
                Text("Searching your care vault")
                    .font(TypeScale.label)
                    .foregroundStyle(DesignTokens.cocoaSoft)
            }
            .frame(minHeight: DesignTokens.controlMinimum)
        case let .failed(message):
            StatusNotice(title: "Search unavailable", detail: message, kind: .warning)
        case .empty:
            noResults
        case .loaded:
            if results.isEmpty {
                noResults
            } else {
                resultList
            }
        }
    }

    private var searchField: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("Search your thread")
                .font(TypeScale.label)
                .foregroundStyle(DesignTokens.cocoa)
            HStack(spacing: DesignTokens.Spacing.small) {
                AppIcon.search.image
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(DesignTokens.cocoa)
                    .accessibilityHidden(true)
                TextField("Try football", text: Binding(get: { query }, set: { query = MemorySearchModel.boundedQuery($0) }))
                    .font(TypeScale.body)
                    .foregroundStyle(DesignTokens.cocoa)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .accessibilityLabel("Search your thread")
                if !query.isEmpty {
                    Button(action: clearSearch) {
                        AppIcon.close.image
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: DesignTokens.controlMinimum, height: DesignTokens.controlMinimum)
                    }
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .accessibilityLabel("Clear memory search")
                }
            }
            .padding(.leading, DesignTokens.Spacing.base)
            .padding(.trailing, DesignTokens.Spacing.small)
            .frame(minHeight: 52)
            .background(DesignTokens.surface)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous)
                    .stroke(DesignTokens.hairline, lineWidth: 1)
            )
        }
    }

    private var prompt: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.compact) {
            KernelGlyph(voice: .candyCorn, height: 18, decorative: true)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                Text("Try “football” to find where that thread appeared in a journal, therapy, and your appointment inbox.")
                    .font(TypeScale.body)
                    .foregroundStyle(DesignTokens.cocoa)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Search runs on this device.")
                    .font(TypeScale.provenance)
                    .foregroundStyle(DesignTokens.cocoaSoft)
            }
        }
        .padding(DesignTokens.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.surfaceWarm)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
    }

    private var resultList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(results.count) \(results.count == 1 ? "result" : "results")")
                .font(TypeScale.sectionCompact)
                .foregroundStyle(DesignTokens.cocoa)
                .padding(.bottom, DesignTokens.Spacing.base)
                .monospacedDigit()
            Divider().overlay(DesignTokens.hairline)
            ForEach(results) { record in
                SearchResultRow(record: record) { open(record) }
            }
        }
    }

    private var noResults: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            KernelGlyph(voice: .candyCorn, height: 20, decorative: true)
            Text("No memories match “\(trimmedQuery)”")
                .font(TypeScale.sectionCompact)
                .foregroundStyle(DesignTokens.cocoa)
                .fixedSize(horizontal: false, vertical: true)
            Text("Try another word or clear the search. Nothing was sent anywhere.")
                .font(TypeScale.label)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .fixedSize(horizontal: false, vertical: true)
            Button("Clear search", action: clearSearch)
                .font(TypeScale.bodyMedium)
                .foregroundStyle(DesignTokens.cocoa)
                .frame(minHeight: DesignTokens.controlMinimum)
        }
        .padding(.vertical, DesignTokens.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider().overlay(DesignTokens.hairline) }
        .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
    }

    private func clearSearch() {
        query = ""
    }

    private func destination(for kind: SearchEntityKind) -> Route {
        switch kind {
        case .journal: .journalDetail
        case .mood: .checkIn
        case .appointment: .therapySession
        case .goal: .goals
        case .talkingPoint: .bringUp
        case .transcript: .therapySession
        case .summary: .therapySession
        }
    }

    private func open(_ record: MemorySearchRecord) {
        if let hit = state.searchResults.first(where: { $0.id == record.id }) {
            if hit.kind == .journal { state.selectJournal(id: hit.entityID) }
            if hit.kind == .appointment { state.selectAppointment(id: hit.entityID) }
        }
        navigation.navigate(to: record.destination)
    }
}

private struct SearchResultRow: View {
    let record: MemorySearchRecord
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                HStack(spacing: DesignTokens.Spacing.small) {
                    Text(record.title)
                        .font(TypeScale.bodyMedium)
                        .foregroundStyle(DesignTokens.cocoa)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    AppIcon.chevronRight.image
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DesignTokens.cocoaSoft)
                }
                Text(record.excerpt)
                    .font(TypeScale.provenance)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                ProvenanceLine(provenance: record.provenance, compact: true)
            }
            .padding(.vertical, DesignTokens.Spacing.base)
            .frame(maxWidth: .infinity, minHeight: DesignTokens.controlMinimum, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(record.title). \(record.excerpt). \(record.provenance.label). \(record.provenance.detail)")
        .accessibilityHint("Opens this memory")
    }
}
