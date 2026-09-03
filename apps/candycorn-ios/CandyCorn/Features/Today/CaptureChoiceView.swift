import SwiftUI

struct CaptureChoice: Identifiable, Sendable {
    let title: String
    let detail: String
    let route: Route
    let icon: AppIcon

    var id: Route { route }
}

struct CaptureChoiceView: View {
    static let choices = [
        CaptureChoice(title: "Talk", detail: "Say it as it comes. Keep the audio or organize it later.", route: .journalVoice, icon: .microphone),
        CaptureChoice(title: "Write", detail: "Start with your own words in a quiet text editor.", route: .journalWrite, icon: .pencil),
        CaptureChoice(title: "Photograph a journal page", detail: "Keep the original page beside extracted text.", route: .journalPhoto, icon: .camera),
        CaptureChoice(title: "Quick mood check-in", detail: "Log mood, anxiety, and energy from 1 to 10.", route: .checkIn, icon: .checkCircle),
    ]

    @Bindable var navigation: NavigationModel

    var body: some View {
        ScreenLayout(
            title: "What feels easiest?",
            subtitle: "Choose one way to get it out. You can organize it later.",
            backAction: navigation.dismissPresentedFlow,
            bottomInset: DesignTokens.Spacing.large
        ) {
            VStack(spacing: 0) {
                Divider().overlay(DesignTokens.hairline)
                ForEach(Self.choices) { choice in
                    choiceRow(choice)
                    Divider().overlay(DesignTokens.hairline)
                }
            }
            privacyStatement
                .padding(.top, DesignTokens.Spacing.xSmall)
        }
    }

    private func choiceRow(_ choice: CaptureChoice) -> some View {
        Button { navigation.navigate(to: choice.route) } label: {
            HStack(spacing: DesignTokens.Spacing.compact) {
                choice.icon.image
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(DesignTokens.orangePressed)
                    .frame(width: 44, height: 44)
                    .overlay(Circle().stroke(DesignTokens.orange, lineWidth: 1))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
                    Text(choice.title)
                        .font(TypeScale.bodyMedium)
                        .foregroundStyle(DesignTokens.cocoa)
                    Text(choice.detail)
                        .font(TypeScale.label)
                        .foregroundStyle(DesignTokens.cocoaSoft)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DesignTokens.Spacing.small)
                AppIcon.chevronRight.image
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.title)
        .accessibilityHint("\(choice.detail) Opens the next screen")
    }

    private var privacyStatement: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.compact) {
            KernelGlyph(voice: .user, height: 18)
                .padding(.top, 2)
            Text("Nothing starts until you choose the next action.")
                .font(TypeScale.provenance)
                .foregroundStyle(DesignTokens.cocoaSoft)
            Spacer(minLength: 0)
        }
        .padding(DesignTokens.Spacing.base)
        .background(DesignTokens.surfaceWarm)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
