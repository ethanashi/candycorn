import Foundation
import SwiftUI

struct AppointmentBriefEditor: Equatable, Sendable {
    static let blankMessage = "Keep text in every brief item or cancel your edits."

    let artifactID: UUID
    private(set) var saved: AppointmentBriefResult
    private(set) var draft: AppointmentBriefResult
    private(set) var isEditing = false
    private(set) var error: String?

    init?(artifact: AIArtifact) {
        guard artifact.kind == .appointmentBrief,
              let result = try? JSONDecoder().decode(AppointmentBriefResult.self, from: artifact.structuredPayload),
              Self.isUsable(result) else { return nil }
        artifactID = artifact.id
        saved = result
        draft = result
    }

    mutating func begin() {
        draft = saved
        error = nil
        isEditing = true
    }

    mutating func update(sectionID: UUID, statementID: UUID, text: String) {
        guard isEditing,
              let sectionIndex = draft.sections.firstIndex(where: { $0.id == sectionID }),
              let statementIndex = draft.sections[sectionIndex].statements.firstIndex(where: { $0.id == statementID }) else {
            return
        }
        let statement = draft.sections[sectionIndex].statements[statementIndex]
        draft.sections[sectionIndex].statements[statementIndex] = EvidenceBackedStatement(
            id: statement.id,
            text: String(text.prefix(4_000)),
            evidence: statement.evidence
        )
        error = nil
    }

    mutating func preparedSave(at date: Date) -> AppointmentBriefResult? {
        guard isEditing, Self.isUsable(draft) else {
            error = Self.blankMessage
            return nil
        }
        var result = draft
        result.userEditedAt = date
        return result
    }

    mutating func commit(_ result: AppointmentBriefResult) {
        guard result.userEditedAt != nil, Self.isUsable(result) else {
            error = "The edited brief could not be saved."
            return
        }
        saved = result
        draft = result
        error = nil
        isEditing = false
    }

    mutating func failSave() {
        error = "The edited brief could not be saved. Your generated brief is unchanged."
    }

    mutating func cancel() {
        draft = saved
        error = nil
        isEditing = false
    }

    static func isUsable(_ result: AppointmentBriefResult) -> Bool {
        guard !result.sections.isEmpty, result.sections.count <= 24 else { return false }
        let statements = result.sections.flatMap(\.statements)
        guard !statements.isEmpty, statements.count <= 120 else { return false }
        return result.sections.allSatisfy { section in
            !section.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !section.statements.isEmpty
                && section.statements.allSatisfy {
                    !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.evidence.isEmpty
                }
        }
    }
}

enum AppointmentBriefSafety {
    private static let tmsUnsafePhrases = [
        "tms caused", "caused by tms", "tms made your", "tms improved", "tms worsened",
        "tms led to", "tms resulted in", "because of tms", "due to tms", "from tms treatment",
        "change your treatment", "adjust your treatment", "stop treatment", "start treatment",
        "increase your dose", "decrease your dose", "change your dose", "skip treatment",
        "treatment provocation", "provocation protocol", "increase stimulation", "decrease stimulation"
    ]

    static func isSafeForTMS(_ result: AppointmentBriefResult) -> Bool {
        guard AppointmentBriefEditor.isUsable(result) else { return false }
        let text = result.sections.flatMap(\.statements).map(\.text).joined(separator: " ").lowercased()
        guard text.count <= 480_000 else { return false }
        return !tmsUnsafePhrases.contains { text.contains($0) }
    }
}

enum AppointmentBriefArtifactReader {
    static func latest(
        kind: Appointment.Kind,
        preferredID: UUID?,
        artifacts: [AIArtifact],
        appointments: [Appointment],
        goals: [Goal],
        talkingPoints: [TalkingPoint]
    ) -> AIArtifact? {
        let candidates = artifacts.filter { $0.kind == .appointmentBrief }
        if let preferredID, let preferred = candidates.first(where: { $0.id == preferredID }),
           let editor = AppointmentBriefEditor(artifact: preferred),
           kind != .tms || AppointmentBriefSafety.isSafeForTMS(editor.saved) {
            return preferred
        }
        let sourceIDs = kindSpecificSourceIDs(
            kind: kind,
            appointments: appointments,
            goals: goals,
            talkingPoints: talkingPoints
        )
        return candidates
            .filter { artifact in artifact.sourceIDs.contains { sourceIDs.contains($0) } }
            .filter { artifact in
                guard let editor = AppointmentBriefEditor(artifact: artifact) else { return false }
                return kind != .tms || AppointmentBriefSafety.isSafeForTMS(editor.saved)
            }
            .max { $0.createdAt < $1.createdAt }
    }

    static func hasUnreadableArtifact(
        kind: Appointment.Kind,
        preferredID: UUID?,
        artifacts: [AIArtifact],
        appointments: [Appointment],
        goals: [Goal],
        talkingPoints: [TalkingPoint]
    ) -> Bool {
        let sourceIDs = kindSpecificSourceIDs(
            kind: kind,
            appointments: appointments,
            goals: goals,
            talkingPoints: talkingPoints
        )
        return artifacts.contains { artifact in
            guard artifact.kind == .appointmentBrief,
                  artifact.id == preferredID || artifact.sourceIDs.contains(where: sourceIDs.contains) else { return false }
            guard let editor = AppointmentBriefEditor(artifact: artifact) else { return true }
            return kind == .tms && !AppointmentBriefSafety.isSafeForTMS(editor.saved)
        }
    }

    private static func kindSpecificSourceIDs(
        kind: Appointment.Kind,
        appointments: [Appointment],
        goals: [Goal],
        talkingPoints: [TalkingPoint]
    ) -> Set<UUID> {
        let appointmentIDs = Set(appointments.filter { $0.kind == kind }.map(\.id))
        let pointIDs = talkingPoints.filter { $0.targetAppointmentKind == kind }.map(\.id)
        let goalIDs = goals.filter { goal in
            guard let sourceID = goal.sourceEntityID else { return false }
            return appointmentIDs.contains(sourceID)
        }.map(\.id)
        return appointmentIDs.union(pointIDs).union(goalIDs)
    }
}

struct AppointmentBriefReadingView: View {
    let result: AppointmentBriefResult
    let artifact: AIArtifact
    let provenanceForSource: (UUID) -> Provenance

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.blockGap) {
            if let editedAt = result.userEditedAt {
                ProvenanceInline(
                    voice: .user,
                    text: "You edited this · \(editedAt.formatted(.dateTime.month(.abbreviated).day())) · Sources unchanged"
                )
            }
            ForEach(result.sections) { section in
                V2Card {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                        HStack(spacing: DesignTokens.Spacing.compact) {
                            IconTile(icon: .sparkles, size: 34)
                            Text(section.title)
                                .font(TypeScale.cardTitle)
                                .foregroundStyle(DesignTokens.cocoa)
                        }
                        ForEach(section.statements) { statement in
                            statementView(statement)
                        }
                    }
                }
            }
        }
    }

    private func statementView(_ statement: EvidenceBackedStatement) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(statement.text)
                .font(TypeScale.body)
                .foregroundStyle(DesignTokens.cocoa)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            ProvenanceStack(provenance: Provenance(
                voice: .candyCorn,
                label: "Candy Corn suggested this wording",
                detail: "\(artifact.provider), \(artifact.model)",
                occurredAt: artifact.createdAt,
                sourceRoute: nil
            ))
            ForEach(Array(statement.evidence.enumerated()), id: \.offset) { _, citation in
                evidenceView(citation)
            }
        }
    }

    private func evidenceView(_ citation: EvidenceCitation) -> some View {
        let provenance = provenanceForSource(citation.sourceID)
        return HStack(alignment: .top, spacing: DesignTokens.Spacing.small) {
            KernelGlyph(voice: provenance.voice, height: 14, decorative: true)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(provenance.label)
                    .font(TypeScale.metaStrong)
                    .foregroundStyle(DesignTokens.cocoa)
                Text("“\(citation.quote)”")
                    .font(TypeScale.meta)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DesignTokens.Spacing.compact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.surfaceWarm)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
