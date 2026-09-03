import SwiftUI

struct TMSPostSessionView: View {
    @Bindable var navigation: NavigationModel
    @State private var snapshot = TMSCheckInSnapshot(mood: 6, anxiety: 5, energy: 4, distress: 5)
    @State private var providerInstructions = "Keep the usual schedule and note anything you want to discuss next time."
    @State private var nextItem = "Ask whether the head pressure is expected to stay this brief."
    @State private var saved = false

    var body: some View {
        if saved { savedView } else { checkInView }
    }

    private var checkInView: some View {
        ScreenLayout(
            title: "After TMS",
            subtitle: "Record what you notice without assigning a cause.",
            backAction: navigation.backAction(for: .tmsPost),
            bottomInset: DesignTokens.Spacing.section
        ) {
            TMSMeasuresEditor(snapshot: $snapshot)
            noteField(title: "Provider instruction notes", text: $providerInstructions)
            ProvenanceLine(provenance: providerProvenance)
            noteField(title: "One thing for next session", text: $nextItem)
            Text("This check-in records timing and context. It does not claim that TMS caused a mood or symptom change.")
                .font(TypeScale.label)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(DesignTokens.Spacing.base)
                .background(DesignTokens.surfaceWarm)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius))
            Button("Save post-session check-in") { saved = true }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var savedView: some View {
        ScreenLayout(
            title: "Post-session check-in saved",
            subtitle: "Saved on this device.",
            backAction: navigation.backAction(for: .tmsPost),
            bottomInset: DesignTokens.Spacing.section
        ) {
            StatusNotice(
                title: "Saved on this device",
                detail: "Your notes are recorded without claiming what caused a change.",
                kind: .saved
            )
            Button("Open History") { navigation.navigate(to: .history) }
                .buttonStyle(PrimaryButtonStyle())
            Button("Prepare for TMS") { navigation.navigate(to: .prepareTMS) }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var providerProvenance: Provenance {
        Provenance(
            voice: .provider,
            label: "TMS team said this",
            detail: "Post-session instructions, Sep 5 at 9:56 AM",
            occurredAt: nil,
            sourceRoute: .tmsPost
        )
    }

    private func noteField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(title).font(TypeScale.sectionCompact)
            TextEditor(text: text)
                .font(TypeScale.body)
                .scrollContentBackground(.hidden)
                .padding(DesignTokens.Spacing.compact)
                .frame(minHeight: 104)
                .background(DesignTokens.surface)
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.controlRadius).stroke(DesignTokens.hairline))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius))
                .accessibilityLabel(title)
        }
        .foregroundStyle(DesignTokens.cocoa)
    }
}
