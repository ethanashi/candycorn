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
                content
            } else {
                ScreenLayout(
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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
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
                Text("Use sample content").font(TypeScale.bodyMedium)
            }
            .tint(DesignTokens.orange)
            .frame(minHeight: DesignTokens.controlMinimum)
            .disabled(isUpdatingSamples)
            Text("Turning this off removes Jamie Rivera’s fictional examples. Your entries stay.")
                .font(TypeScale.provenance)
                .foregroundStyle(DesignTokens.cocoaSoft)
        }
        .padding(.bottom, DesignTokens.Spacing.base)
        .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
    }

    private var retentionChoices: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Raw audio retention").font(TypeScale.sectionCompact)
                .padding(.bottom, DesignTokens.Spacing.compact)
            Divider().overlay(DesignTokens.hairline)
            ForEach(AudioRetentionChoice.allCases) { choice in
                SettingsChoiceRow(
                    title: choice.title,
                    detail: choice.detail,
                    selected: state.settings.audioRetention == choice,
                    disabled: updatingRetention != nil,
                    action: {
                        guard updatingRetention == nil else { return }
                        updatingRetention = choice
                        var settings = state.settings
                        settings.audioRetention = choice
                        Task {
                            _ = await state.updateSettings(settings)
                            updatingRetention = nil
                        }
                    }
                )
            }
        }
    }

    private var exportControls: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("Export your care vault").font(TypeScale.sectionCompact)
            Text("Creates a temporary folder with Markdown entries, originals, and a JSON index.")
                .font(TypeScale.label).foregroundStyle(DesignTokens.cocoaSoft)
            Button(exportButtonTitle) { Task { await state.makeExport() } }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(state.exportState == .exporting)
            if case let .failed(message) = state.exportState {
                StatusNotice(title: "Export failed", detail: message, kind: .warning)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.base)
        .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
    }

    private var deleteControls: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("Delete everything").font(TypeScale.sectionCompact)
            Text("This removes the care vault and every attachment from this device.")
                .font(TypeScale.label).foregroundStyle(DesignTokens.cocoaSoft)
            if showingDeleteConfirmation {
                TextField("Type DELETE", text: $deleteText)
                    .textInputAutocapitalization(.characters)
                    .font(TypeScale.body)
                    .padding(DesignTokens.Spacing.compact)
                    .overlay(RoundedRectangle(cornerRadius: DesignTokens.controlRadius).stroke(DesignTokens.hairline))
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
                    .buttonStyle(SecondaryButtonStyle())
            }
            if state.exportState == .deleted {
                StatusNotice(title: "Care vault deleted", detail: "The app is ready for a new entry. Sample content stays off.", kind: .saved)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.base)
    }

    private var exportButtonTitle: String {
        state.exportState == .exporting ? "Creating export" : "Create export"
    }

    private func cleanupExport() {
        Task { await state.cleanupExport() }
    }
}
