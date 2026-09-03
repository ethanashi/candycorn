import SwiftUI

struct StatusNotice: View {
    enum Kind {
        case information
        case saved
        case warning
    }

    let title: String
    var detail: String?
    var kind: Kind = .information

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.compact) {
            Image(systemName: symbol)
                .foregroundStyle(accent)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
                Text(title)
                    .font(TypeScale.bodyMedium)
                    .foregroundStyle(DesignTokens.cocoa)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(TypeScale.provenance)
                        .foregroundStyle(DesignTokens.cocoaSoft)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DesignTokens.Spacing.base)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch kind {
        case .information: AppIcon.shield.rawValue
        case .saved: AppIcon.checkCircle.rawValue
        case .warning: "exclamationmark.triangle"
        }
    }

    private var accent: Color {
        switch kind {
        case .information: DesignTokens.yellowDeep
        case .saved: DesignTokens.sage
        case .warning: DesignTokens.rose
        }
    }

    private var background: Color {
        kind == .warning ? DesignTokens.rose.opacity(0.12) : DesignTokens.surfaceWarm
    }
}
