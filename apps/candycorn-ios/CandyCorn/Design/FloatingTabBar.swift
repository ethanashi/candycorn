import SwiftUI

struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab
    var onSelect: ((AppTab) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    selectedTab = tab
                    onSelect?(tab)
                } label: {
                    VStack(spacing: 5) {
                        tab.symbol.image
                            .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                            .symbolVariant(isSelected ? .fill : .none)
                        Text(tab.title)
                            .font(TypeScale.tabLabel)
                            .lineLimit(1)
                    }
                    .foregroundStyle(isSelected ? DesignTokens.orange : DesignTokens.tabInactive)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .overlay(alignment: .top) {
                        if isSelected {
                            Capsule()
                                .fill(DesignTokens.orange)
                                .frame(width: 22, height: 3)
                                .offset(y: -6)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.small)
        .padding(.vertical, DesignTokens.Spacing.small)
        .background(DesignTokens.surface)
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(DesignTokens.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: DesignTokens.cocoa.opacity(0.06), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Main navigation")
    }
}
