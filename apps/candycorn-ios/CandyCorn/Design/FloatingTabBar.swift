import SwiftUI

struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab
    var onSelect: ((AppTab) -> Void)?

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xSmall) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selectedTab = tab
                    onSelect?(tab)
                } label: {
                    VStack(spacing: DesignTokens.Spacing.xSmall) {
                        tab.symbol.image
                            .font(.system(size: 19, weight: selectedTab == tab ? .semibold : .regular))
                        Text(tab.title)
                            .font(TypeScale.provenance)
                            .lineLimit(1)
                    }
                    .foregroundStyle(selectedTab == tab ? DesignTokens.cocoa : DesignTokens.cocoaSoft)
                    .frame(maxWidth: .infinity, minHeight: DesignTokens.controlMinimum)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.small)
        .padding(.vertical, DesignTokens.Spacing.small)
        .background(DesignTokens.surface)
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous).stroke(DesignTokens.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous))
        .shadow(color: DesignTokens.cocoa.opacity(0.06), radius: 8, x: 0, y: 2)
        .padding(.horizontal, DesignTokens.screenInset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Main navigation")
    }
}
