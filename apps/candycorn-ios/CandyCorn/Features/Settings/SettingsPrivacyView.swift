import SwiftUI

struct SettingsPrivacyView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState

    var body: some View {
        V2Screen(
            title: "Privacy",
            subtitle: "Your record stays understandable and under your control.",
            backAction: navigation.backAction(for: .settingsPrivacy)
        ) {
            V2GroupCard(title: "Where things live") {
                V2ListRow(
                    icon: .phone,
                    title: "Stored on this phone",
                    detail: "Originals and notes stay in your encrypted local vault.",
                    trailing: .check
                )
                V2ListRow(
                    icon: .cloudUpload,
                    title: "Cloud upload",
                    detail: "Only when you tap Send. You see exactly what goes first.",
                    trailing: .check
                )
                V2ListRow(
                    icon: .waveform,
                    title: "Raw audio",
                    detail: "You choose what happens to recordings.",
                    value: state.settings.audioRetention.shortTitle
                ) { navigation.openSettings(.data) }
            }
            V2GroupCard(title: "What Candy Corn never does") {
                V2ListRow(icon: .personSlash, title: "No accounts", detail: "No sign-in and no profile.", trailing: .check)
                V2ListRow(icon: .eyeSlash, title: "No analytics or tracking", detail: "No advertising or tracking SDKs.", trailing: .check)
            }
            V2Card {
                HStack(alignment: .top, spacing: DesignTokens.Spacing.compact) {
                    KernelGlyph(voice: .provider, height: 18, decorative: true)
                        .padding(.top, 3)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("About and limitations")
                            .font(TypeScale.cardTitle)
                            .foregroundStyle(DesignTokens.cocoa)
                        Text("Candy Corn helps you organize your own care record. It is not a therapist, medical advice, or a crisis service. In the US, 988 is there any time.")
                            .font(TypeScale.label)
                            .foregroundStyle(DesignTokens.cocoaSoft)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            V2GroupCard {
                V2ListRow(
                    icon: .sliders,
                    title: "Review AI and processing",
                    value: state.aiMode.shortTitle,
                    divider: false
                ) { navigation.openSettings(.ai) }
            }
        }
    }
}
