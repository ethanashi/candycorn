import SwiftUI

struct ScreenLayout<Content: View>: View {
    let title: String
    var subtitle: String?
    var backAction: (() -> Void)?
    var backLabel: String
    var trailing: AnyView?
    var bottomInset: CGFloat
    private let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        backAction: (() -> Void)? = nil,
        backLabel: String = "Back",
        trailing: AnyView? = nil,
        bottomInset: CGFloat = 112,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.backAction = backAction
        self.backLabel = backLabel
        self.trailing = trailing
        self.bottomInset = bottomInset
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.large) {
                header
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.screenInset)
            .padding(.top, DesignTokens.Spacing.compact)
            .padding(.bottom, bottomInset)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DesignTokens.canvas.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            if backAction != nil || trailing != nil {
                HStack {
                    if let backAction {
                        Button(action: backAction) {
                            Label(backLabel, systemImage: AppIcon.back.rawValue)
                                .labelStyle(.iconOnly)
                                .frame(width: DesignTokens.controlMinimum, height: DesignTokens.controlMinimum)
                        }
                        .foregroundStyle(DesignTokens.cocoa)
                        .accessibilityLabel(backLabel)
                    }
                    Spacer()
                    trailing
                }
            }
            Text(title)
                .font(TypeScale.pageTitle)
                .foregroundStyle(DesignTokens.cocoa)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(TypeScale.body)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
