import SwiftUI

enum AudioRetentionChoice: String, CaseIterable, Codable, Identifiable, Sendable {
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
        case .keep: "Keep the original beside its notes."
        case .deleteAfterVerification: "Delete only after you confirm the transcript in a later version."
        case .ask: "Decide separately after each recording."
        }
    }
}

struct SettingsDataInteractionState: Equatable, Sendable {
    private(set) var retention: AudioRetentionChoice = .ask
    private(set) var showsExportPreview = false
    private(set) var isConfirmingReset = false
    private(set) var resetComplete = false

    mutating func selectRetention(_ choice: AudioRetentionChoice) { retention = choice }
    mutating func toggleExportPreview() { showsExportPreview.toggle() }
    mutating func beginReset() { isConfirmingReset = true }
    mutating func cancelReset() { isConfirmingReset = false }

    @MainActor @discardableResult
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
    var embedded = false
    @State private var deleteText = ""
    @State private var showingDeleteConfirmation = false
    @State private var showingShare = false
    @State private var isUpdatingSamples = false
    @State private var updatingRetention: AudioRetentionChoice?
    @State private var isDeleting = false

    var body: some View {
        Group {
            if embedded {
                VStack(alignment: .leading, spacing: DesignTokens.blockGap) { content }
            } else {
                V2Screen(
                    title: "Data and export",
                    subtitle: "Choose what stays on this phone and export a readable copy.",
                    backAction: navigation.backAction(for: .settingsData)
                ) {
                    content
                }
            }
        }
        .sheet(isPresented: $showingShare, onDismiss: cleanupExport) {
            if case let .ready(package) = state.exportState {
                VStack(spacing: DesignTokens.Spacing.large) {
                    Text("Your export is ready").font(TypeScale.section)
                    ShareLink(item: package.directoryURL) {
                        Label("Share export folder", systemImage: AppIcon.download.rawValue)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(DesignTokens.Spacing.large)
                .presentationDetents([.medium])
            }
        }
        .onChange(of: state.exportState) { _, value in
            if case .ready = value { showingShare = true }
        }
    }

    @ViewBuilder private var content: some View {
        sampleContent
        retentionChoices
        exportControls
        deleteControls
    }

    private var sampleContent: some View {
        V2Card {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: Binding(
                    get: { state.settings.useSampleContent },
                    set: { enabled in
                        guard !isUpdatingSamples else { return }
                        isUpdatingSamples = true
                        Task {
                            _ = await state.setSampleContentEnabled(enabled)
                            isUpdatingSamples = false
                        }
                    }
                )) {
                    HStack(spacing: DesignTokens.Spacing.compact) {
                        IconTile(icon: .toggle, size: 34)
                        Text("Use sample content")
                            .font(TypeScale.rowTitleCompact)
                            .foregroundStyle(DesignTokens.cocoa)
                    }
                }
                .tint(DesignTokens.orange)
                .frame(minHeight: DesignTokens.controlMinimum)
                .disabled(isUpdatingSamples)
                Text("Turning this off removes Jamie Rivera’s fictional examples. Your entries stay.")
                    .font(TypeScale.meta)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var retentionChoices: some View {
        V2GroupCard(title: "Raw audio") {
            ForEach(AudioRetentionChoice.allCases) { choice in
                V2ChoiceRow(
                    title: choice.title,
                    detail: choice.detail,
                    selected: state.settings.audioRetention == choice,
                    disabled: updatingRetention != nil
                ) {
                    guard updatingRetention == nil, state.settings.audioRetention != choice else { return }
                    updatingRetention = choice
                    var settings = state.settings
                    settings.audioRetention = choice
                    Task {
                        _ = await state.updateSettings(settings)
                        updatingRetention = nil
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Raw audio retention")
    }

    private var exportControls: some View {
        V2Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                HStack(spacing: DesignTokens.Spacing.compact) {
                    IconTile(icon: .share, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export everything")
                            .font(TypeScale.cardTitle)
                            .foregroundStyle(DesignTokens.cocoa)
                        Text("A folder with Markdown entries, originals, and a JSON index.")
                            .font(TypeScale.meta)
                            .foregroundStyle(DesignTokens.cocoaSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button(exportButtonTitle) { Task { await state.makeExport() } }
                    .buttonStyle(CompactDarkButtonStyle())
                    .disabled(state.exportState == .exporting)
                if case let .failed(message) = state.exportState {
                    StatusNotice(title: "Export failed", detail: message, kind: .warning)
                }
            }
        }
    }

    private var deleteControls: some View {
        V2Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                HStack(spacing: DesignTokens.Spacing.compact) {
                    AppIcon.trash.image
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(DesignTokens.rose)
                        .frame(width: 34, height: 34)
                        .background(DesignTokens.rose.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Delete everything")
                            .font(TypeScale.cardTitle)
                            .foregroundStyle(DesignTokens.rose)
                        Text("Removes the vault and every attachment from this phone.")
                            .font(TypeScale.meta)
                            .foregroundStyle(DesignTokens.cocoaSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if showingDeleteConfirmation {
                    TextField("Type DELETE", text: $deleteText)
                        .textInputAutocapitalization(.characters)
                        .font(TypeScale.label)
                        .padding(.horizontal, DesignTokens.Spacing.compact)
                        .frame(minHeight: DesignTokens.controlMinimum)
                        .background(DesignTokens.surfaceWarm)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Button(isDeleting ? "Deleting" : "Delete everything", role: .destructive) {
                        guard !isDeleting else { return }
                        isDeleting = true
                        Task {
                            _ = await state.deleteEverything(typedText: deleteText)
                            isDeleting = false
                        }
                    }
                    .buttonStyle(DangerButtonStyle())
                    .disabled(isDeleting || DeleteConfirmation(typedText: deleteText) == nil)
                } else {
                    Button("Delete everything") { showingDeleteConfirmation = true }
                        .buttonStyle(CompactGhostButtonStyle())
                }
                if state.exportState == .deleted {
                    StatusNotice(title: "Care vault deleted", detail: "The app is ready for a new entry. Sample content stays off.", kind: .saved)
                }
            }
        }
    }

    private var exportButtonTitle: String {
        state.exportState == .exporting ? "Creating export" : "Create export"
    }

    private func cleanupExport() {
        Task { await state.cleanupExport() }
    }
}
