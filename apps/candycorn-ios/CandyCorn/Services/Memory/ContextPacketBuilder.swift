import Foundation

struct MemoryRetrievalRequest: Equatable, Sendable {
    let appointmentKind: Appointment.Kind
    let window: DateInterval
    let now: Date
}

struct ContextPacketLimits: Equatable, Sendable {
    static let appointment = ContextPacketLimits(
        maximumItems: 32,
        maximumCharacters: 12_000,
        maximumCharactersPerItem: 1_500,
        maximumSearchQueries: 8,
        maximumItemsPerKind: 10
    )

    let maximumItems: Int
    let maximumCharacters: Int
    let maximumCharactersPerItem: Int
    let maximumSearchQueries: Int
    let maximumItemsPerKind: Int
}

struct ContextPacketItem: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case sessionSummary, transcriptEvidence, homework, activeGoal
        case goalProgress, talkingPoint, journal, moodTrend, moodLog
    }

    let id: UUID
    let sourceIDs: [UUID]
    let kind: Kind
    let title: String
    let text: String
    let occurredAt: Date?
    let provenance: ProvenanceVoice
    let evidence: [EvidenceCitation]
    let relevanceRank: Int?

    var sourceKind: SourceTextDocument.Kind {
        switch kind {
        case .sessionSummary, .transcriptEvidence: .sessionNotes
        case .homework: .homework
        case .activeGoal, .goalProgress: .goal
        case .talkingPoint: .talkingPoint
        case .journal: .journal
        case .moodTrend, .moodLog: .moodTrend
        }
    }
}

struct ContextPacket: Equatable, Sendable {
    let request: MemoryRetrievalRequest
    let items: [ContextPacketItem]
    let text: String
    let omittedItemCount: Int

    var characterCount: Int { text.count }

    var sources: [SourceTextDocument] {
        items.map {
            SourceTextDocument(
                id: $0.id,
                kind: $0.sourceKind,
                title: $0.title,
                text: $0.text,
                occurredAt: $0.occurredAt
            )
        }
    }
}

protocol MemoryRetrieving: Sendable {
    func retrieve(_ request: MemoryRetrievalRequest) async throws -> ContextPacket
}

struct ContextPacketBuilder: Sendable {
    let limits: ContextPacketLimits

    init(limits: ContextPacketLimits = .appointment) {
        self.limits = limits
    }

    func build(
        request: MemoryRetrievalRequest,
        candidates: [ContextPacketItem],
        alreadyOmitted: Int = 0
    ) throws -> ContextPacket {
        guard limits.maximumItems >= 0, limits.maximumCharacters > 0,
              limits.maximumCharactersPerItem > 0, limits.maximumSearchQueries >= 0,
              limits.maximumItemsPerKind >= 0, alreadyOmitted >= 0 else {
            throw VaultRepositoryError.invalidInput
        }
        var text = Self.truncate(Self.header(for: request), to: limits.maximumCharacters)
        var items: [ContextPacketItem] = []
        var seen: Set<UUID> = []
        var kindCounts: [ContextPacketItem.Kind: Int] = [:]

        for candidate in candidates {
            guard items.count < limits.maximumItems,
                  !seen.contains(candidate.id),
                  kindCounts[candidate.kind, default: 0] < limits.maximumItemsPerKind,
                  let normalized = normalized(candidate) else { continue }
            let separator = "\n\n"
            let prefix = Self.blockPrefix(for: normalized)
            let available = limits.maximumCharacters - text.count - separator.count - prefix.count
            guard available > 0 else { continue }
            let itemText = Self.truncate(normalized.text, to: min(available, limits.maximumCharactersPerItem))
            guard !itemText.isEmpty else { continue }
            let accepted = Self.replacingText(in: normalized, with: itemText)
            text += separator + prefix + itemText
            items.append(accepted)
            seen.insert(accepted.id)
            kindCounts[accepted.kind, default: 0] += 1
        }

        guard text.count <= limits.maximumCharacters,
              items.count <= limits.maximumItems,
              items.allSatisfy({ !$0.sourceIDs.isEmpty }) else {
            throw VaultRepositoryError.invalidInput
        }
        return ContextPacket(
            request: request,
            items: items,
            text: text,
            omittedItemCount: alreadyOmitted + candidates.count - items.count
        )
    }

    private func normalized(_ item: ContextPacketItem) -> ContextPacketItem? {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !text.isEmpty, !item.sourceIDs.isEmpty else { return nil }
        let sourceIDs = Self.unique(item.sourceIDs)
        guard !sourceIDs.isEmpty else { return nil }
        return ContextPacketItem(
            id: item.id,
            sourceIDs: sourceIDs,
            kind: item.kind,
            title: title,
            text: Self.truncate(text, to: limits.maximumCharactersPerItem),
            occurredAt: item.occurredAt,
            provenance: item.provenance,
            evidence: item.evidence,
            relevanceRank: item.relevanceRank
        )
    }

    private static func header(for request: MemoryRetrievalRequest) -> String {
        """
        Context packet
        Appointment kind: \(request.appointmentKind.rawValue)
        Window start: \(timestamp(request.window.start))
        Window end: \(timestamp(request.window.end))
        """
    }

    private static func blockPrefix(for item: ContextPacketItem) -> String {
        var lines = [
            "Item",
            "Kind: \(item.kind.rawValue)",
            "ID: \(item.id.uuidString.lowercased())",
            "Provenance: \(item.provenance.rawValue)",
        ]
        if let occurredAt = item.occurredAt {
            lines.append("Occurred at: \(timestamp(occurredAt))")
        }
        lines.append("Title: \(item.title)")
        lines.append("Text: ")
        return lines.joined(separator: "\n")
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func replacingText(in item: ContextPacketItem, with text: String) -> ContextPacketItem {
        ContextPacketItem(
            id: item.id,
            sourceIDs: item.sourceIDs,
            kind: item.kind,
            title: item.title,
            text: text,
            occurredAt: item.occurredAt,
            provenance: item.provenance,
            evidence: item.evidence,
            relevanceRank: item.relevanceRank
        )
    }

    private static func truncate(_ value: String, to limit: Int) -> String {
        guard limit > 0, value.count > limit else { return limit > 0 ? value : "" }
        return String(value.prefix(limit))
    }

    private static func unique(_ values: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return values.filter { seen.insert($0).inserted }
    }
}
