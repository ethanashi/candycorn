import Foundation
import SwiftUI

enum ContinuityFixtures {
    static let tmsTalkingPoint = TalkingPoint(
        id: fixtureID("50000000-0000-0000-0000-000000000004"),
        text: "Share sleep and headache notes before the next TMS visit",
        source: .session,
        sourceID: SeededData.completedTMSID,
        targetAppointmentKind: .tms,
        isImportant: true,
        status: .open,
        createdAt: Date(timeIntervalSince1970: 1_788_625_920),
        provenance: Provenance(
            voice: .provider,
            label: "TMS team asked you to track this",
            detail: "TMS visit, Sep 5 at 9:52 AM",
            occurredAt: Date(timeIntervalSince1970: 1_788_625_920),
            sourceRoute: .tmsPost
        )
    )

    static let manualTalkingPointID = fixtureID("50000000-0000-0000-0000-000000000005")

    private static func fixtureID(_ value: String) -> UUID {
        guard let id = UUID(uuidString: value) else {
            preconditionFailure("Continuity fixture UUID must be valid")
        }
        return id
    }
}

struct ManualTalkingPointDraft: Equatable, Sendable {
    static let maximumLength = 200
    var text = ""
    var error: String?

    mutating func updateText(_ value: String) {
        text = String(value.prefix(Self.maximumLength))
        error = nil
    }

    mutating func makeTalkingPoint() -> TalkingPoint? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "Write what you want to bring up first."
            return nil
        }
        error = nil
        return TalkingPoint(
            id: ContinuityFixtures.manualTalkingPointID,
            text: trimmed,
            source: .manual,
            sourceID: nil,
            targetAppointmentKind: .therapy,
            isImportant: false,
            status: .open,
            createdAt: Date(timeIntervalSince1970: 1_788_668_400),
            provenance: Provenance(
                voice: .user,
                label: "You added this",
                detail: "Bring up next time, Sep 5",
                occurredAt: Date(timeIntervalSince1970: 1_788_668_400),
                sourceRoute: .bringUp
            )
        )
    }
}

enum BringUpLogic {
    @MainActor
    static func ensureTMSPoint(in state: DemoState) {
        guard !state.talkingPoints.contains(where: { $0.id == ContinuityFixtures.tmsTalkingPoint.id }) else {
            return
        }
        precondition(state.addTalkingPoint(ContinuityFixtures.tmsTalkingPoint))
    }

    static func targetLabel(for point: TalkingPoint) -> String {
        switch point.targetAppointmentKind {
        case .therapy: "Therapy with Dr. Elena Park, Sep 9"
        case .tms: "Next TMS visit"
        case .psychiatry: "Next psychiatry visit"
        case .other, nil: "Next care conversation"
        }
    }
}

struct BringUpView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @State private var draft = ManualTalkingPointDraft()

    private var openItems: [TalkingPoint] {
        state.talkingPoints.filter { $0.status == .open }
    }

    private var hasManualItem: Bool {
        state.talkingPoints.contains { $0.id == ContinuityFixtures.manualTalkingPointID }
    }

    var body: some View {
        ScreenLayout(
            title: "Bring up next time",
            subtitle: "A short inbox for the conversations you do not want to lose.",
            backAction: navigation.backAction(for: .bringUp)
        ) {
            if openItems.isEmpty {
                emptyState
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Divider().overlay(DesignTokens.hairline)
                    ForEach(openItems) { point in
                        TalkingPointRow(point: point) { status in
                            state.updateTalkingPoint(id: point.id, status: status)
                        }
                    }
                }
            }
            manualSection
                .padding(.top, DesignTokens.Spacing.base)
        }
        .onAppear { BringUpLogic.ensureTMSPoint(in: state) }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            KernelGlyph(voice: .user, height: 20, decorative: true)
            Text("Nothing waiting for the next appointment")
                .font(TypeScale.sectionCompact)
            Text("You can return here whenever something comes up.")
                .font(TypeScale.label)
                .foregroundStyle(DesignTokens.cocoaSoft)
        }
        .foregroundStyle(DesignTokens.cocoa)
        .padding(.vertical, DesignTokens.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider().overlay(DesignTokens.hairline) }
        .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
    }

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Divider().overlay(DesignTokens.hairline)
                .padding(.bottom, DesignTokens.Spacing.base)
            Text("Add your own")
                .font(TypeScale.sectionCompact)
            if hasManualItem {
                Text("Your manual item is in the inbox. You can discuss or dismiss it above.")
                    .font(TypeScale.label)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("What do you want to remember?")
                    .font(TypeScale.label)
                TextEditor(text: Binding(get: { draft.text }, set: { draft.updateText($0) }))
                    .font(TypeScale.body)
                    .foregroundStyle(DesignTokens.cocoa)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 92)
                    .padding(DesignTokens.Spacing.compact)
                    .background(DesignTokens.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous)
                            .stroke(DesignTokens.hairline, lineWidth: 1)
                    )
                    .accessibilityLabel("What do you want to remember?")
                if let error = draft.error {
                    Text(error)
                        .font(TypeScale.provenance)
                        .foregroundStyle(DesignTokens.rose)
                        .accessibilityLabel("Error. \(error)")
                }
                Button("Add to inbox", action: addManualItem)
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private func addManualItem() {
        guard let point = draft.makeTalkingPoint() else { return }
        if state.addTalkingPoint(point) {
            draft = ManualTalkingPointDraft()
        } else {
            draft.error = "This item is already in your inbox."
        }
    }
}

private struct TalkingPointRow: View {
    let point: TalkingPoint
    let onStatus: (TalkingPoint.Status) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(point.text)
                .font(TypeScale.bodyMedium)
                .foregroundStyle(DesignTokens.cocoa)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(point.isImportant ? "Important" : "Normal priority") · \(BringUpLogic.targetLabel(for: point))")
                .font(TypeScale.provenance)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .fixedSize(horizontal: false, vertical: true)
            ProvenanceLine(provenance: point.provenance, compact: true)
            HStack(spacing: DesignTokens.Spacing.small) {
                actionButton("Discussed", status: .discussed)
                actionButton("Dismiss", status: .dismissed)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.medium)
        .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
    }

    private func actionButton(_ title: String, status: TalkingPoint.Status) -> some View {
        Button(title) { onStatus(status) }
            .font(TypeScale.label)
            .foregroundStyle(DesignTokens.cocoa)
            .frame(minWidth: 96, minHeight: DesignTokens.controlMinimum)
            .background(DesignTokens.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DesignTokens.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityLabel("\(title): \(point.text)")
    }
}
