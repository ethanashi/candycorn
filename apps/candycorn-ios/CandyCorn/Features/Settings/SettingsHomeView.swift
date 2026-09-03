import SwiftUI

/// Settings tab root (v2): three groups of plain rows with honest values. Each row opens a detail screen.
struct SettingsHomeView: View {
    @Bindable var navigation: NavigationModel
    @Bindable var state: DemoState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.blockGap) {
                V2TitleRow(
                    title: "Settings",
                    trailing: AnyView(
                        Text(String(SeededData.patientName.prefix(1)))
                            .font(TypeScale.rowTitleCompact)
                            .foregroundStyle(DesignTokens.cocoa)
                            .frame(width: 40, height: 40)
                            .background(DesignTokens.surfaceWarm)
                            .clipShape(Circle())
                            .accessibilityLabel(SeededData.patientName)
                    )
                )
                group("Privacy") {
                    row(icon: .phone, title: "Stored on this phone", value: nil, check: true) { navigation.openSettings(.privacy) }
                    row(icon: .cloudUpload, title: "Cloud upload", value: "Only when you tap Send") { navigation.openSettings(.privacy) }
                    row(icon: .waveform, title: "Raw audio", value: state.settings.audioRetention.shortTitle, chevron: true) { navigation.openSettings(.data) }
                }
                group("AI") {
                    row(icon: .sliders, title: "Mode", value: state.aiMode.shortTitle, chevron: true) { navigation.openSettings(.ai) }
                    row(icon: .cpu, title: "Model", value: modelTitle, chevron: true) { navigation.openSettings(.ai) }
                    row(icon: .key, title: "OpenRouter key", value: state.hasOpenRouterKey ? "Added" : "Not added", check: state.hasOpenRouterKey, chevron: !state.hasOpenRouterKey) { navigation.openSettings(.ai) }
                }
                group("Data") {
                    row(icon: .share, title: "Export everything", value: nil, chevron: true) { navigation.openSettings(.data) }
                    row(icon: .toggle, title: "Sample content", value: state.settings.useSampleContent ? "On" : "Off", chevron: true) { navigation.openSettings(.data) }
                    row(icon: .trash, title: "Delete everything", value: nil, danger: true) { navigation.openSettings(.data) }
                }
                Text("Candy Corn is not a therapist or a crisis service. In the US, 988 is there any time.")
                    .font(TypeScale.provenance)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DesignTokens.Spacing.xSmall)
            }
            .padding(.horizontal, DesignTokens.screenInset)
            .padding(.top, DesignTokens.Spacing.small)
            .padding(.bottom, DesignTokens.Spacing.large)
        }
        .background(DesignTokens.canvas.ignoresSafeArea())
    }

    private var modelTitle: String {
        let id = state.aiConfiguration.organizerModelID
        if id.contains("deepseek-v4-flash") { return "DeepSeek V4 Flash" }
        if id.contains("deepseek-v4-pro") { return "DeepSeek V4 Pro" }
        return id.split(separator: "/").last.map(String.init) ?? id
    }

    private func group<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        V2Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(TypeScale.metaStrong)
                    .foregroundStyle(DesignTokens.cocoaSoft)
                    .padding(.horizontal, DesignTokens.Spacing.base)
                    .padding(.top, DesignTokens.Spacing.compact)
                    .padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)
                rows()
            }
        }
    }

    private func row(icon: AppIcon, title: String, value: String?, check: Bool = false, chevron: Bool = false, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.compact) {
                icon.image
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(danger ? DesignTokens.rose : DesignTokens.cocoa)
                    .frame(width: 34, height: 34)
                    .background(danger ? DesignTokens.rose.opacity(0.12) : DesignTokens.surfaceWarm)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                Text(title)
                    .font(TypeScale.rowTitleCompact)
                    .foregroundStyle(danger ? DesignTokens.rose : DesignTokens.cocoa)
                Spacer(minLength: DesignTokens.Spacing.small)
                HStack(spacing: 4) {
                    if let value {
                        Text(value)
                            .font(TypeScale.provenance)
                            .foregroundStyle(check ? DesignTokens.sage : DesignTokens.cocoaSoft)
                            .lineLimit(1)
                    }
                    if check {
                        AppIcon.check.image.font(.system(size: 13, weight: .bold)).foregroundStyle(DesignTokens.sage)
                    } else if chevron {
                        AppIcon.chevronRight.image.font(.system(size: 13, weight: .semibold)).foregroundStyle(DesignTokens.cocoaSoft)
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.base)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(DesignTokens.hairline).frame(height: 1).padding(.horizontal, DesignTokens.Spacing.base) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value.map { "\(title), \($0)" } ?? title)
    }
}

extension AIMode {
    var shortTitle: String {
        switch self {
        case .off: "Off"
        case .organizer: "Organizer"
        case .reflection: "Reflection"
        }
    }
}

extension AudioRetentionChoice {
    var shortTitle: String {
        switch self {
        case .keep: "Keep"
        case .deleteAfterVerification: "Delete after verifying"
        case .ask: "Ask each time"
        }
    }
}
