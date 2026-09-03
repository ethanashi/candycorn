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
        V2Screen(
            title: "What feels easiest?",
            subtitle: "Choose one way to get it out. You can organize it later.",
            backAction: navigation.dismissPresentedFlow,
            backLabel: "Close",
            backIcon: .close,
            bottomInset: DesignTokens.Spacing.large
        ) {
            V2GroupCard {
                ForEach(Self.choices) { choice in
                    V2ListRow(
                        icon: choice.icon,
                        title: choice.title,
                        detail: choice.detail,
                        divider: choice.route != Self.choices.first?.route
                    ) { navigation.navigate(to: choice.route) }
                    .accessibilityHint("Opens the next screen")
                }
            }
            privacyStatement
        }
    }

    private var privacyStatement: some View {
        ProvenanceInline(voice: .user, text: "Nothing starts until you choose the next action.")
            .padding(.horizontal, DesignTokens.Spacing.xSmall)
    }
}
