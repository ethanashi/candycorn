import SwiftUI

struct SettingsPrivacyView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState

    var body: some View {
        ScreenLayout(
            title: title,
            subtitle: subtitle
        ) {
            SettingsSectionPicker(navigation: navigation)
            sectionContent
        }
    }

    @ViewBuilder private var sectionContent: some View {
        switch navigation.selectedSettingsSection {
        case .privacy:
            privacyContent
        case .ai:
            SettingsAIView(navigation: navigation, state: state, embedded: true)
        case .data:
            SettingsDataView(navigation: navigation, state: state, embedded: true)
        }
    }

    private var title: String {
        switch navigation.selectedSettingsSection {
        case .privacy: "Privacy"
        case .ai: "AI and processing"
        case .data: "Data and export"
        }
    }

    private var subtitle: String {
        switch navigation.selectedSettingsSection {
        case .privacy: "Your private record stays understandable and under your control."
        case .ai: "AI is off by default. Your local journal works without it."
        case .data: "Choose what stays on this phone and export a readable copy."
        }
    }

    private var privacyContent: some View {
        Group {
            VStack(alignment: .leading, spacing: 0) {
                Text("Privacy status")
                    .font(TypeScale.sectionCompact)
                    .foregroundStyle(DesignTokens.cocoa)
                    .padding(.bottom, DesignTokens.Spacing.compact)
                Divider().overlay(DesignTokens.hairline)
                SettingsStatusRow(
                    status: "Stored on this device",
                    detail: "Originals and notes stay in your encrypted local care vault.",
                    voice: .user
                )
                SettingsStatusRow(
                    status: "Cloud upload: only when AI is on",
                    detail: "Nothing uploads while AI is off. You choose what is sent when processing is enabled."
                )
                SettingsStatusRow(
                    status: "Raw audio retention: you decide",
                    detail: "No recording is active here. Choose a retention rule in Data and export.",
                    voice: .user
                )
                SettingsStatusRow(
                    status: "No accounts or analytics",
                    detail: "No sign-in, advertising, analytics, or tracking."
                )
            }
            limitations
            Button {
                navigation.openSettings(.ai)
            } label: {
                HStack(spacing: DesignTokens.Spacing.compact) {
                    Text("Review AI and processing")
                        .font(TypeScale.bodyMedium)
                    Spacer(minLength: DesignTokens.Spacing.small)
                    AppIcon.chevronRight.image
                }
                .foregroundStyle(DesignTokens.orangePressed)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens AI settings")
        }
    }

    private var limitations: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.compact) {
            KernelGlyph(voice: .provider, height: 18, decorative: true)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                Text("About and limitations")
                    .font(TypeScale.bodyMedium)
                    .foregroundStyle(DesignTokens.cocoa)
                Text("Candy Corn helps you organize your own care record. It is not a therapist, medical advice, or a crisis service. Contact local emergency or crisis support when you need immediate help.")
                    .font(TypeScale.label)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.medium)
        .overlay(alignment: .top) { Divider().overlay(DesignTokens.hairline) }
        .overlay(alignment: .bottom) { Divider().overlay(DesignTokens.hairline) }
        .accessibilityElement(children: .combine)
    }
}
