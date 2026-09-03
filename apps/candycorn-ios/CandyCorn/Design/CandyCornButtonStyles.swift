import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeScale.button)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: DesignTokens.primaryButtonHeight)
            .padding(.horizontal, DesignTokens.Spacing.base)
            .background(configuration.isPressed ? DesignTokens.orangePressed : DesignTokens.orange)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeScale.button)
            .foregroundStyle(DesignTokens.cocoa)
            .frame(maxWidth: .infinity, minHeight: DesignTokens.primaryButtonHeight)
            .padding(.horizontal, DesignTokens.Spacing.base)
            .background(configuration.isPressed ? DesignTokens.surfaceWarm : DesignTokens.surface)
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous).stroke(DesignTokens.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous))
    }
}

struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TypeScale.button)
            .foregroundStyle(DesignTokens.cocoa)
            .frame(maxWidth: .infinity, minHeight: DesignTokens.primaryButtonHeight)
            .padding(.horizontal, DesignTokens.Spacing.base)
            .background(DesignTokens.rose.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous))
    }
}
