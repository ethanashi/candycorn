import SwiftUI

struct AIProcessingStatePresentation: Equatable, Sendable {
    let title: String
    let detail: String?

    static func make(for state: AIProcessingState) -> AIProcessingStatePresentation? {
        switch state {
        case .idle:
            nil
        case .processing:
            AIProcessingStatePresentation(title: "Sending to Candy Corn", detail: "Keep this sheet open while processing finishes.")
        case .succeeded:
            AIProcessingStatePresentation(title: "Finished", detail: "Your original source is unchanged.")
        case let .failed(message):
            AIProcessingStatePresentation(title: "Could not finish", detail: message)
        }
    }
}

struct AIProcessingStateView: View {
    let state: AIProcessingState

    var body: some View {
        if let presentation = AIProcessingStatePresentation.make(for: state) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.compact) {
                KernelGlyph(voice: .candyCorn, height: 18)
                    .padding(.top, DesignTokens.Spacing.xSmall)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
                    Text(presentation.title)
                        .font(TypeScale.bodyMedium)
                        .foregroundStyle(DesignTokens.cocoa)
                    if let detail = presentation.detail {
                        Text(detail)
                            .font(TypeScale.label)
                            .foregroundStyle(DesignTokens.cocoaSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(DesignTokens.Spacing.compact)
            .frame(maxWidth: .infinity, minHeight: DesignTokens.controlMinimum, alignment: .leading)
            .background(DesignTokens.surface)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous)
                    .stroke(DesignTokens.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel([presentation.title, presentation.detail].compactMap(\.self).joined(separator: ". "))
        }
    }
}
