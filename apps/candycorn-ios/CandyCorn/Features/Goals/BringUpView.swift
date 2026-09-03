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
    @State private var isSaving = false
    @State private var showsClosed = false

    private var openItems: [TalkingPoint] {
        state.talkingPoints.filter { $0.status == .open }
    }

    private var closedItems: [TalkingPoint] {
        state.talkingPoints.filter { $0.status != .open }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.blockGap) {
                HStack(spacing: DesignTokens.Spacing.small) {
                    if let back = navigation.backAction(for: .bringUp) {
                        Button(action: back) {
                            AppIcon.back.image
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(DesignTokens.cocoa)
                                .frame(width: DesignTokens.controlMinimum, height: DesignTokens.controlMinimum)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back")
                    }
                    Spacer()
                }
                .frame(height: DesignTokens.controlMinimum)
                V2TitleRow(title: "Bring up next time")
                SectionLine(title: openItems.isEmpty ? "Nothing waiting" : "For \(targetSummary)", trailing: openItems.isEmpty ? nil : "\(openItems.count) pinned")
                if openItems.isEmpty {
                    V2Card(background: DesignTokens.surfaceWarm, showsBorder: false) {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                            Text("Nothing waiting for the next appointment")
                                .font(TypeScale.cardTitle)
                                .foregroundStyle(DesignTokens.cocoa)
                            Text("Pin a thought from any journal, or add one below.")
                                .font(TypeScale.label)
                                .foregroundStyle(DesignTokens.cocoaSoft)
                        }
                    }
                } else {
                    ForEach(openItems) { point in
                        TalkingPointCard(point: point) { status in
                            Task { _ = await state.transitionTalkingPoint(id: point.id, to: status) }
                        }
                    }
                }
                manualSection
                if !closedItems.isEmpty {
                    closedSection
                }
            }
            .padding(.horizontal, DesignTokens.screenInset)
            .padding(.top, DesignTokens.Spacing.xSmall)
            .padding(.bottom, DesignTokens.tabBarClearance)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DesignTokens.canvas.ignoresSafeArea())
    }

    private var targetSummary: String {
        let kinds = Set(openItems.compactMap(\.targetAppointmentKind))
        if kinds == [.therapy] { return "therapy" }
        if kinds == [.tms] { return "TMS" }
        return "your next appointments"
    }

    private var manualSection: some View {
        V2Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                Text("Add your own")
                    .font(TypeScale.cardTitle)
                    .foregroundStyle(DesignTokens.cocoa)
                TextEditor(text: Binding(get: { draft.text }, set: { draft.updateText($0) }))
                    .font(TypeScale.body)
                    .foregroundStyle(DesignTokens.cocoa)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 84)
                    .padding(DesignTokens.Spacing.compact)
                    .background(DesignTokens.surfaceWarm)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if draft.text.isEmpty {
                            Text("What do you want to remember?")
                                .font(TypeScale.body)
                                .foregroundStyle(DesignTokens.cocoaSoft)
                                .padding(DesignTokens.Spacing.compact + 4)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel("What do you want to remember?")
                if let error = draft.error {
                    Text(error).font(TypeScale.provenance).foregroundStyle(DesignTokens.rose)
                }
                Button(isSaving ? "Adding" : "Add to next appointment", action: addManualItem)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isSaving)
            }
        }
    }

    private var closedSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Button {
                showsClosed.toggle()
            } label: {
                SectionLine(title: "Discussed or dismissed", trailing: "\(closedItems.count)")
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Discussed or dismissed items, \(closedItems.count)")
            .accessibilityValue(showsClosed ? "Expanded" : "Collapsed")
            if showsClosed {
                V2Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(closedItems.enumerated()), id: \.element.id) { index, point in
                            if index > 0 { Rectangle().fill(DesignTokens.hairline).frame(height: 1).padding(.horizontal, DesignTokens.Spacing.base) }
                            HStack(spacing: DesignTokens.Spacing.compact) {
                                Text(point.text)
                                    .font(TypeScale.label)
                                    .foregroundStyle(DesignTokens.cocoaSoft)
                                    .strikethrough(point.status == .dismissed, color: DesignTokens.cocoaSoft)
                                Spacer()
                                Button("Reopen") {
                                    Task { _ = await state.transitionTalkingPoint(id: point.id, to: .open) }
                                }
                                .font(TypeScale.metaStrong)
                                .foregroundStyle(DesignTokens.cocoa)
                                .frame(minHeight: DesignTokens.controlMinimum)
                            }
                            .padding(.horizontal, DesignTokens.Spacing.base)
                            .padding(.vertical, DesignTokens.Spacing.xSmall)
                        }
                    }
                }
            }
        }
    }

    private func addManualItem() {
        let text = draft.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isSaving else {
            draft.error = "Write what you want to bring up first."
            return
        }
        isSaving = true
        Task {
            if await state.createTalkingPoint(text: text) != nil {
                draft = ManualTalkingPointDraft()
            } else {
                draft.error = "This item could not be saved. Try again."
            }
            isSaving = false
        }
    }
}

private struct TalkingPointCard: View {
    let point: TalkingPoint
    let onStatus: (TalkingPoint.Status) -> Void

    var body: some View {
        V2Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                HStack(alignment: .top, spacing: DesignTokens.Spacing.compact) {
                    KernelGlyph(voice: point.provenance.voice, height: 20, decorative: true)
                        .padding(.top, 2)
                    Text(point.text)
                        .font(TypeScale.rowTitle)
                        .foregroundStyle(DesignTokens.cocoa)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if point.isImportant {
                        Text("Important")
                            .font(TypeScale.metaStrong)
                            .foregroundStyle(DesignTokens.cocoa)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 26)
                            .background(DesignTokens.yellow)
                            .clipShape(Capsule())
                            .accessibilityLabel("Important")
                    }
                }
                ProvenanceInline(voice: point.provenance.voice, text: "\(point.provenance.label) · \(point.provenance.detail)")
                HStack(spacing: DesignTokens.Spacing.small) {
                    Button("Discussed") { onStatus(.discussed) }
                        .buttonStyle(CompactDarkButtonStyle())
                        .accessibilityLabel("Mark discussed: \(point.text)")
                    Button("Dismiss") { onStatus(.dismissed) }
                        .buttonStyle(CompactGhostButtonStyle())
                        .accessibilityLabel("Dismiss: \(point.text)")
                }
                .padding(.top, DesignTokens.Spacing.xSmall)
            }
        }
    }
}
