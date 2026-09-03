import SwiftUI

struct SettingsPrivacyView: View {
    @Bindable var navigation: NavigationModel

    var body: some View {
        ScreenLayout(
            title: "Privacy",
            subtitle: "Your private record should stay understandable and under your control."
        ) {
            SettingsSectionPicker(current: .privacy, navigation: navigation)
            VStack(alignment: .leading, spacing: 0) {
                Text("Privacy status")
                    .font(TypeScale.sectionCompact)
                    .foregroundStyle(DesignTokens.cocoa)
                    .padding(.bottom, DesignTokens.Spacing.compact)
                Divider().overlay(DesignTokens.hairline)
                SettingsStatusRow(
                    status: "Stored on this device",
                    detail: "The native app is designed to keep originals in an encrypted local vault. This shell keeps only in-memory changes.",
                    voice: .user
                )
                SettingsStatusRow(
                    status: "Cloud upload: only when AI is on",
                    detail: "Nothing uploads in this shell. Later processing will show what is selected before a request."
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
                navigation.navigate(to: .settingsAI)
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
