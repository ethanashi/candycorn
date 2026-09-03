import SwiftUI

struct UnderlinePicker<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.medium) {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        VStack(spacing: DesignTokens.Spacing.small) {
                            Text(title(option))
                                .font(TypeScale.label)
                                .foregroundStyle(selection == option ? DesignTokens.cocoa : DesignTokens.cocoaSoft)
                            Rectangle()
                                .fill(selection == option ? DesignTokens.orange : Color.clear)
                                .frame(height: 2)
                        }
                        .frame(minHeight: DesignTokens.controlMinimum)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == option ? .isSelected : [])
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
