import SwiftUI

enum AudioRetentionChoice: String, CaseIterable, Identifiable, Sendable {
    case keep
    case deleteAfterVerification
    case ask

    var id: Self { self }

    var title: String {
        switch self {
        case .keep: "Keep raw recording"
        case .deleteAfterVerification: "Delete after transcript verification"
        case .ask: "Ask every time"
        }
    }

    var detail: String {
        switch self {
        case .keep: "Keep the original beside its transcript."
        case .deleteAfterVerification: "Intended behavior after you confirm the transcript."
        case .ask: "Decide separately after each recording."
        }
    }
}

struct SettingsDataInteractionState: Equatable, Sendable {
    private(set) var retention: AudioRetentionChoice = .ask
    private(set) var showsExportPreview = false
    private(set) var isConfirmingReset = false
    private(set) var resetComplete = false

    mutating func selectRetention(_ choice: AudioRetentionChoice) {
        retention = choice
        resetComplete = false
    }

    mutating func toggleExportPreview() {
        showsExportPreview.toggle()
        resetComplete = false
    }

    mutating func beginReset() {
        guard !isConfirmingReset else { return }
        isConfirmingReset = true
        resetComplete = false
    }

    mutating func cancelReset() {
        isConfirmingReset = false
    }

    @MainActor
    @discardableResult
    mutating func confirmReset(in state: DemoState) -> Bool {
        guard isConfirmingReset, !resetComplete else { return false }
        state.reset()
        retention = .ask
        showsExportPreview = false
        isConfirmingReset = false
        resetComplete = true
        return true
    }
}

struct SettingsDataView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    @State private var local = SettingsDataInteractionState()
    var embedded = false

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                ScreenLayout(title: "Data and export", subtitle: "Choose what stays on this phone and export a readable copy.") {
                    SettingsSectionPicker(navigation: navigation)
                    content
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        retentionChoices
        exportPreview
        resetDemo
    }

    private var retentionChoices: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Raw audio retention")
                .font(TypeScale.sectionCompact)
                .foregroundStyle(DesignTokens.cocoa)
                .padding(.bottom, DesignTokens.Spacing.compact)
            Divider().overlay(DesignTokens.hairline)
            ForEach(AudioRetentionChoice.allCases) { choice in
                SettingsChoiceRow(
                    title: choice.title,
                    detail: choice.detail,
                    selected: local.retention == choice,
                    action: { local.selectRetention(choice) }
                )
            }
        }
    }

    private var exportPreview: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.compact) {
            KernelGlyph(voice: .user, height: 18, decorative: true)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                Text("Export preview")
                    .font(TypeScale.sectionCompact)
                    .foregroundStyle(DesignTokens.cocoa)
                Text("Export is planned to build a readable archive of your originals and notes. Previewing creates no file.")
                    .font(TypeScale.label)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    local.toggleExportPreview()
                } label: {
                    Label(
                        local.showsExportPreview ? "Hide archive preview" : "Preview archive contents",
                        systemImage: AppIcon.download.rawValue
                    )
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityValue(local.showsExportPreview ? "Expanded" : "Collapsed")
                if local.showsExportPreview {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        previewLine("Original journals and organized copies")
                        previewLine("Session audio, transcripts, and summaries you retained")
                        previewLine("Goals, mood check-ins, and appointment briefs")
                        previewLine("A plain provenance record for generated items")
                    }
                    .padding(.top, DesignTokens.Spacing.small)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.vertical, DesignTokens.Spacing.medium)
        .overlay(alignment: .top) { Divider().overlay(DesignTokens.hairline) }
        .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
    }

    private var resetDemo: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.compact) {
            KernelGlyph(voice: .provider, height: 18, decorative: true)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                Text("Reset demo")
                    .font(TypeScale.sectionCompact)
                    .foregroundStyle(DesignTokens.cocoa)
                Text("Restore the fictional Jamie Rivera thread and clear changes made during this visit.")
                    .font(TypeScale.label)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .fixedSize(horizontal: false, vertical: true)
                resetControls
                if local.resetComplete {
                    StatusNotice(title: "Seeded demo restored.", kind: .saved)
                        .accessibilityLabel("Seeded demo restored")
                }
            }
        }
        .padding(.vertical, DesignTokens.Spacing.medium)
        .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
    }

    @ViewBuilder
    private var resetControls: some View {
        if local.isConfirmingReset {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                Text("This clears only temporary changes. Reset now?")
                    .font(TypeScale.label)
                    .foregroundStyle(DesignTokens.cocoa)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: DesignTokens.Spacing.small) {
                    Button("Cancel") { local.cancelReset() }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Reset now") { _ = local.confirmReset(in: state) }
                        .buttonStyle(DangerButtonStyle())
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Confirm reset demo")
        } else {
            Button(action: { local.beginReset() }) {
                Label("Reset demo", systemImage: AppIcon.trash.rawValue)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func previewLine(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.small) {
            Circle()
                .fill(DesignTokens.yellowDeep)
                .frame(width: 5, height: 5)
            Text(text)
                .font(TypeScale.provenance)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
