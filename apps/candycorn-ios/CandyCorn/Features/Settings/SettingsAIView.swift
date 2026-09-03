import SwiftUI

struct AIProcessingStatus: Equatable, Sendable {
    let journal: String
    let voice: String
}

enum AISettingsLogic {
    static func processingStatus(mode: AIMode, provider: AIProvider) -> AIProcessingStatus {
        if mode == .off || provider == .off {
            return AIProcessingStatus(journal: "Journal intelligence: Off", voice: "Voice transcription: Off")
        }
        if provider == .router {
            return AIProcessingStatus(journal: "Journal intelligence: Cloud (router)", voice: "Voice transcription: Cloud (router)")
        }
        return AIProcessingStatus(
            journal: "Journal intelligence: Waiting for on-device availability",
            voice: "Voice transcription: Waiting for on-device availability"
        )
    }

    static func leavesDeviceCopy(mode: AIMode, provider: AIProvider) -> String {
        if mode == .off || provider == .off {
            return "Nothing is sent for AI processing."
        }
        if provider == .onDeviceWhenAvailable {
            return "Nothing is sent until a supported on-device provider is available and selected."
        }
        if mode == .organizer {
            return "Selected journal text and selected audio for transcription may be sent through the cloud router."
        }
        return "Selected journal text, transcript excerpts, and selected audio for transcription may be sent through the cloud router."
    }

    static func modeDescription(_ mode: AIMode) -> String {
        switch mode {
        case .off: "No organizing or reflection."
        case .organizer: "Cleans up wording, summarizes, and finds candidate items."
        case .reflection: "Adds optional connections across saved entries. Every connection stays a suggestion."
        }
    }

    @MainActor
    static func selectMode(_ mode: AIMode, in state: DemoState) {
        let providerWasOff = state.aiProvider == .off
        state.setAIMode(mode)
        if mode != .off && providerWasOff {
            state.setAIProvider(.off)
        }
    }

    @MainActor
    static func canSelect(_ provider: AIProvider, in state: DemoState) -> Bool {
        switch provider {
        case .onDeviceWhenAvailable: false
        case .router: state.aiMode != .off && state.routerAvailable
        case .off: true
        }
    }
}

struct SettingsAIView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState
    var embedded = false

    private var status: AIProcessingStatus {
        AISettingsLogic.processingStatus(mode: state.aiMode, provider: state.aiProvider)
    }

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                ScreenLayout(title: "AI and processing", subtitle: "AI is off by default. Your local journal works without it.") {
                    SettingsSectionPicker(navigation: navigation)
                    content
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
            processingLedger
            if !state.routerAvailable {
                unavailableRouter
            }
            modeChoice
            providerChoice
            StatusNotice(
                title: "What leaves this device",
                detail: AISettingsLogic.leavesDeviceCopy(mode: state.aiMode, provider: state.aiProvider),
                kind: state.aiMode == .off || state.aiProvider == .off ? .saved : .information
            )
    }

    private var processingLedger: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Processing status")
                .font(TypeScale.sectionCompact)
                .foregroundStyle(DesignTokens.cocoa)
                .padding(.bottom, DesignTokens.Spacing.compact)
            Divider().overlay(DesignTokens.hairline)
            SettingsStatusRow(
                status: status.journal,
                detail: state.aiMode == .off ? "Your original journal stays readable." : "First-version language tasks are planned for the hosted router."
            )
            SettingsStatusRow(
                status: status.voice,
                detail: state.aiMode == .off ? "Saved originals remain available." : "Only audio you select for transcription would be included."
            )
        }
    }

    private var unavailableRouter: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("Cloud router unavailable")
                .font(TypeScale.bodyMedium)
                .foregroundStyle(DesignTokens.cocoa)
            Text("Organization is unavailable right now. Your original journals, transcripts, and audio remain available.")
                .font(TypeScale.provenance)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .fixedSize(horizontal: false, vertical: true)
            Button("Turn AI off") { AISettingsLogic.selectMode(.off, in: state) }
                .font(TypeScale.bodyMedium)
                .foregroundStyle(DesignTokens.orangePressed)
                .frame(minHeight: DesignTokens.controlMinimum)
        }
        .padding(DesignTokens.Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.surfaceWarm)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var modeChoice: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
            Text("AI mode")
                .font(TypeScale.sectionCompact)
                .foregroundStyle(DesignTokens.cocoa)
            Text("Choose how much help you want. Suggestions never change your originals.")
                .font(TypeScale.label)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .fixedSize(horizontal: false, vertical: true)
            UnderlinePicker(options: AIMode.allCases, selection: modeBinding) { modeTitle($0) }
            Text(AISettingsLogic.modeDescription(state.aiMode))
                .font(TypeScale.label)
                .foregroundStyle(DesignTokens.cocoaSoft)
                .frame(minHeight: 64, alignment: .topLeading)
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
                title: "On-device when available",
                detail: "Available on supported iPhones in a later version.",
                selected: state.aiProvider == .onDeviceWhenAvailable,
                disabled: true,
                action: {}
            )
            SettingsChoiceRow(
                title: "Router",
                detail: state.routerAvailable ? "First-version cloud processing." : "Unavailable right now. Originals are unaffected.",
                selected: state.aiProvider == .router,
                disabled: !AISettingsLogic.canSelect(.router, in: state),
                action: { state.setAIProvider(.router) }
            )
            SettingsChoiceRow(
                title: "Off",
                detail: "No AI processing leaves this device.",
                selected: state.aiProvider == .off,
                action: { state.setAIProvider(.off) }
            )
        }
    }

    private var modeBinding: Binding<AIMode> {
        Binding(
            get: { state.aiMode },
            set: { AISettingsLogic.selectMode($0, in: state) }
        )
    }

    private func modeTitle(_ mode: AIMode) -> String {
        switch mode {
        case .off: "Off"
        case .organizer: "Organizer"
        case .reflection: "Reflection"
        }
    }
}
