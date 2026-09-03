import SwiftUI

struct AIProcessingStatus: Equatable, Sendable {
    let journal: String
    let voice: String
}

enum AISettingsValidationError: Error, Equatable, Sendable {
    case emptyKey
    case keyTooLong
    case emptyOrganizerModel
    case organizerModelTooLong
    case emptyVisionModel
    case visionModelTooLong

    var message: String {
        switch self {
        case .emptyKey: "Enter an OpenRouter key."
        case .keyTooLong: "That key is too long. Check it and try again."
        case .emptyOrganizerModel: "Enter an organizer model."
        case .organizerModelTooLong: "The organizer model is too long."
        case .emptyVisionModel: "Enter a photo-to-text model."
        case .visionModelTooLong: "The photo-to-text model is too long."
        }
    }
}

enum AISettingsLogic {
    static let reflectionNote = "Reflection uses Organizer for now. It does not start a conversation."

    static func processingStatus(mode: AIMode, provider: AIProvider) -> AIProcessingStatus {
        if mode == .off || provider == .off {
            return AIProcessingStatus(
                journal: "Journal intelligence: Off",
                voice: "Voice transcription: Not yet available"
            )
        }
        if provider == .router {
            return AIProcessingStatus(
                journal: "Journal intelligence: Cloud (router)",
                voice: "Voice transcription: Not yet available"
            )
        }
        return AIProcessingStatus(
            journal: "Journal intelligence: Not yet available",
            voice: "Voice transcription: Not yet available"
        )
    }

    static func leavesDeviceCopy(mode: AIMode, provider: AIProvider) -> String {
        guard mode != .off, provider != .off else {
            return "Nothing is sent for AI processing."
        }
        guard provider == .router else {
            return "Nothing is sent until a supported on-device provider is available."
        }
        if mode == .reflection {
            return "Reflection uses Organizer for now. Transcript excerpts are not sent. Selected journal text is sent only after you tap Send."
        }
        return "Selected journal text may be sent only after you tap Send."
    }

    static func canSelectRouter(mode: AIMode, hasKey: Bool) -> Bool {
        mode != .off && hasKey
    }

    @MainActor
    static func canSelect(_ provider: AIProvider, in state: DemoState) -> Bool {
        switch provider {
        case .onDeviceWhenAvailable: false
        case .router:
            canSelectRouter(mode: state.aiMode, hasKey: state.hasOpenRouterKey)
                && state.routerAvailable
        case .off: true
        }
    }

    @MainActor
    static func selectMode(_ mode: AIMode, in state: DemoState) {
        state.setAIMode(mode)
    }

    static func modeDescription(_ mode: AIMode) -> String {
        switch mode {
        case .off: "No organizing or reflection. Manual features stay available."
        case .organizer: "Cleans up wording, summarizes, and finds items you may choose to carry forward."
        case .reflection: reflectionNote
        }
    }

    static func normalizedKey(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw AISettingsValidationError.emptyKey }
        guard normalized.count <= OpenRouterAPIKeyStore.maximumCharacterCount else {
            throw AISettingsValidationError.keyTooLong
        }
        return normalized
    }

    static func validatedConfiguration(
        organizerModelID: String,
        visionModelID: String
    ) throws -> AIModelConfiguration {
        let organizer = organizerModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let vision = visionModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !organizer.isEmpty else { throw AISettingsValidationError.emptyOrganizerModel }
        guard organizer.count <= UserDefaultsAIConfigurationStore.maximumModelIdentifierCount else {
            throw AISettingsValidationError.organizerModelTooLong
        }
        guard !vision.isEmpty else { throw AISettingsValidationError.emptyVisionModel }
        guard vision.count <= UserDefaultsAIConfigurationStore.maximumModelIdentifierCount else {
            throw AISettingsValidationError.visionModelTooLong
        }
        return AIModelConfiguration(organizerModelID: organizer, visionModelID: vision)
    }
}

struct SettingsAIView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    var embedded: Bool

    @State private var showingKeySheet = false
    @State private var showingRemoveConfirmation = false
    @State private var didOpenScreenshotSheet = false
    @State private var isUpdatingChoice = false
    @State private var isRemovingKey = false
    @State private var isSavingModels = false
    @State private var organizerModelID: String
    @State private var visionModelID: String
    @State private var localError: String?
    @State private var modelSaveConfirmation: String?

    init(navigation: NavigationModel, state: DemoState, embedded: Bool = false) {
        self.navigation = navigation
        self.state = state
        self.embedded = embedded
        _organizerModelID = State(initialValue: state.aiConfiguration.organizerModelID)
        _visionModelID = State(initialValue: state.aiConfiguration.visionModelID)
    }

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                ScreenLayout(
                    title: "AI and processing",
                    subtitle: "AI is off by default. Your local journal works without it."
                ) {
                    SettingsSectionPicker(navigation: navigation)
                    content
                }
            }
        }
        .sheet(isPresented: $showingKeySheet) {
            OpenRouterKeySheet(onSave: saveKey)
        }
        .confirmationDialog(
            "Remove OpenRouter key?",
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove key", role: .destructive) { removeKey() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Router processing turns off immediately. Your saved entries and manual features are unchanged.")
        }
        .onAppear(perform: openScreenshotSheetIfNeeded)
        .onChange(of: state.aiConfiguration) { _, configuration in
            organizerModelID = configuration.organizerModelID
            visionModelID = configuration.visionModelID
        }
    }

    @ViewBuilder private var content: some View {
        AIProcessingStatusView(
            mode: state.aiMode,
            provider: state.aiProvider,
            hasOpenRouterKey: state.hasOpenRouterKey,
            configuration: state.aiConfiguration
        )
        modeChoice
        providerChoice
        keyControls
        modelControls
        StatusNotice(
            title: "What leaves this device",
            detail: "Nothing uploads automatically. Before every cloud request, you see the exact "
                + "entries and character or image counts. Nothing is sent until you tap Send.",
            kind: state.aiMode == .off || state.aiProvider == .off ? .saved : .information
        )
        if let localError {
            StatusNotice(title: "Settings not changed", detail: localError, kind: .warning)
        }
    }

    private var modeChoice: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            Text("AI mode")
                .font(TypeScale.sectionCompact)
                .foregroundStyle(DesignTokens.cocoa)
            Text("Choose how much organizing help you want. Suggestions never change your originals.")
                .font(TypeScale.label)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .fixedSize(horizontal: false, vertical: true)
            UnderlinePicker(options: AIMode.allCases, selection: modeBinding) { modeTitle($0) }
                .disabled(isUpdatingChoice)
            Text(AISettingsLogic.modeDescription(state.aiMode))
                .font(TypeScale.label)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Current AI mode. \(AISettingsLogic.modeDescription(state.aiMode))")
        }
    }

    private var providerChoice: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Processing provider")
                .font(TypeScale.sectionCompact)
                .foregroundStyle(DesignTokens.cocoa)
                .padding(.bottom, DesignTokens.Spacing.compact)
            Divider().overlay(DesignTokens.hairline)
            SettingsChoiceRow(
                title: "Router",
                detail: routerDetail,
                selected: state.aiProvider == .router,
                disabled: isUpdatingChoice || !AISettingsLogic.canSelect(.router, in: state),
                action: { updateProvider(.router) }
            )
            SettingsChoiceRow(
                title: "On-device when available",
                detail: "Not yet available.",
                selected: state.aiProvider == .onDeviceWhenAvailable,
                disabled: true,
                action: {}
            )
            SettingsChoiceRow(
                title: "Off",
                detail: "No AI processing leaves this device.",
                selected: state.aiProvider == .off,
                disabled: isUpdatingChoice,
                action: { updateProvider(.off) }
            )
        }
    }

    private var keyControls: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("OpenRouter key")
                .font(TypeScale.sectionCompact)
                .foregroundStyle(DesignTokens.cocoa)
            SettingsStatusRow(
                status: state.hasOpenRouterKey ? "Key saved" : "No key saved",
                detail: state.hasOpenRouterKey
                    ? "Stored securely in this iPhone's Keychain. The saved key is never displayed."
                    : "Add your own key to make Router available.",
                voice: .user
            )
            Button("Paste OpenRouter key") { showingKeySheet = true }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isRemovingKey)
            if state.hasOpenRouterKey {
                Button(isRemovingKey ? "Removing key" : "Remove key", role: .destructive) {
                    showingRemoveConfirmation = true
                }
                .buttonStyle(DangerButtonStyle())
                .disabled(isRemovingKey)
            }
        }
    }

    private var modelControls: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            Text("Cloud models")
                .font(TypeScale.sectionCompact)
                .foregroundStyle(DesignTokens.cocoa)
            Text("These model IDs are read when you tap Send. Voice transcription is not yet available.")
                .font(TypeScale.label)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .fixedSize(horizontal: false, vertical: true)
            modelField(
                label: "Organizer model",
                value: $organizerModelID,
                accessibilityLabel: "Organizer model ID"
            )
            modelField(
                label: "Photo-to-text model",
                value: $visionModelID,
                accessibilityLabel: "Photo-to-text model ID"
            )
            Button(isSavingModels ? "Saving models" : "Save models", action: saveModels)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSavingModels || !modelsAreDirty)
            Button("Restore defaults", action: restoreModelDefaults)
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isSavingModels || modelFieldsAreDefaults)
            if let modelSaveConfirmation {
                Text(modelSaveConfirmation)
                    .font(TypeScale.label)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .accessibilityLabel(modelSaveConfirmation)
            }
        }
    }

    private func modelField(
        label: String,
        value: Binding<String>,
        accessibilityLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
            Text(label)
                .font(TypeScale.label)
                .foregroundStyle(DesignTokens.cocoaSoft)
            TextField(label, text: boundedModelBinding(value))
                .font(TypeScale.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .padding(DesignTokens.Spacing.compact)
                .frame(minHeight: DesignTokens.controlMinimum)
                .background(DesignTokens.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous)
                        .stroke(DesignTokens.hairline, lineWidth: 1)
                )
                .accessibilityLabel(accessibilityLabel)
        }
    }

    private var modeBinding: Binding<AIMode> {
        Binding(get: { state.aiMode }, set: { updateMode($0) })
    }

    private var routerDetail: String {
        if state.aiMode == .off { return "Choose Organizer or Reflection first." }
        if !state.hasOpenRouterKey { return "Unavailable until you add an OpenRouter key." }
        return "Cloud processing through your saved key."
    }

    private var modelsAreDirty: Bool {
        organizerModelID != state.aiConfiguration.organizerModelID
            || visionModelID != state.aiConfiguration.visionModelID
    }

    private var modelFieldsAreDefaults: Bool {
        organizerModelID == AIModelConfiguration.defaults.organizerModelID
            && visionModelID == AIModelConfiguration.defaults.visionModelID
    }

    private func modeTitle(_ mode: AIMode) -> String {
        switch mode {
        case .off: "Off"
        case .organizer: "Organizer"
        case .reflection: "Reflection"
        }
    }

    private func boundedModelBinding(_ binding: Binding<String>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue },
            set: {
                binding.wrappedValue = String(
                    $0.prefix(UserDefaultsAIConfigurationStore.maximumModelIdentifierCount + 1)
                )
                modelSaveConfirmation = nil
            }
        )
    }

    private func updateMode(_ mode: AIMode) {
        guard !isUpdatingChoice else { return }
        isUpdatingChoice = true
        localError = nil
        AISettingsLogic.selectMode(mode, in: state)
        Task {
            let saved = await state.updateSettings(state.settings)
            if !saved { localError = "The AI mode could not be saved. Try again." }
            isUpdatingChoice = false
        }
    }

    private func updateProvider(_ provider: AIProvider) {
        guard !isUpdatingChoice, AISettingsLogic.canSelect(provider, in: state) else { return }
        isUpdatingChoice = true
        localError = nil
        Task {
            let saved = await state.persistAIProvider(provider)
            if !saved { localError = "The processing provider could not be saved. Try again." }
            isUpdatingChoice = false
        }
    }

    private func saveKey(_ value: String) -> Bool {
        localError = nil
        let saved = state.storeOpenRouterKey(value)
        if !saved { localError = "That router key could not be saved. Check it and try again." }
        return saved
    }

    private func removeKey() {
        guard !isRemovingKey else { return }
        isRemovingKey = true
        localError = nil
        Task {
            let removed = await state.removeOpenRouterKey()
            if !removed { localError = "The router key could not be removed. Try again." }
            isRemovingKey = false
        }
    }

    private func saveModels() {
        guard !isSavingModels else { return }
        isSavingModels = true
        localError = nil
        modelSaveConfirmation = nil
        do {
            let configuration = try AISettingsLogic.validatedConfiguration(
                organizerModelID: organizerModelID,
                visionModelID: visionModelID
            )
            if state.updateAIConfiguration(configuration) {
                modelSaveConfirmation = "Model settings saved."
            } else {
                localError = "Those model settings could not be saved. Try again."
            }
        } catch let error as AISettingsValidationError {
            localError = error.message
        } catch {
            localError = "Those model settings could not be saved. Try again."
        }
        isSavingModels = false
    }

    private func restoreModelDefaults() {
        organizerModelID = AIModelConfiguration.defaults.organizerModelID
        visionModelID = AIModelConfiguration.defaults.visionModelID
        saveModels()
    }

    private func openScreenshotSheetIfNeeded() {
        guard !didOpenScreenshotSheet,
              state.dependencies.screenshotScenario == .openRouterKey else { return }
        didOpenScreenshotSheet = true
        showingKeySheet = true
    }
}
