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
        V2Screen(
            title: "Search memory",
            subtitle: "Journals, sessions, goals, and pinned items. Runs on this device.",
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
        HStack(spacing: DesignTokens.Spacing.small) {
            AppIcon.search.image
                .font(.system(size: 17, weight: .medium))
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
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: DesignTokens.controlMinimum, height: DesignTokens.controlMinimum)
                }
                .foregroundStyle(DesignTokens.cocoaSoft)
                .accessibilityLabel("Clear memory search")
            }
        }
        .padding(.leading, DesignTokens.Spacing.base)
        .padding(.trailing, DesignTokens.Spacing.small)
        .frame(minHeight: 52)
        .background(DesignTokens.surfaceWarm)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var prompt: some View {
        V2Card {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.compact) {
                IconTile(icon: .search, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Try “football”")
                        .font(TypeScale.cardTitle)
                        .foregroundStyle(DesignTokens.cocoa)
                    Text("Find where a thread appeared across journals, therapy, and your appointment inbox.")
                        .font(TypeScale.meta)
                        .foregroundStyle(DesignTokens.cocoaSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var resultList: some View {
        V2GroupCard(title: "\(results.count) \(results.count == 1 ? "result" : "results")") {
            ForEach(results) { record in
                V2ListRow(
                    icon: icon(for: record.destination),
                    title: record.title,
                    detail: "\(record.excerpt)\n\(record.provenance.label) · \(record.provenance.detail)"
                ) { open(record) }
                .accessibilityHint("Opens this memory")
            }
        }
    }

    private var noResults: some View {
        V2Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                Text("No memories match “\(trimmedQuery)”")
                    .font(TypeScale.cardTitle)
                    .foregroundStyle(DesignTokens.cocoa)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Try another word or clear the search. Nothing was sent anywhere.")
                    .font(TypeScale.meta)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Clear search", action: clearSearch)
                    .buttonStyle(CompactGhostButtonStyle())
            }
        }
    }

    private func icon(for destination: Route) -> AppIcon {
        switch destination {
        case .journalDetail: .journal
        case .therapySession, .tmsPost: .waveform
        case .goals: .flag
        case .bringUp: .listPlus
        case .checkIn: .heart
        default: .search
        }
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
