import SwiftUI

struct ProvenanceLine: View {
    let provenance: Provenance
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.small) {
            KernelGlyph(voice: provenance.voice, height: compact ? 16 : 18, decorative: true)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xSmall) {
                Text(provenance.label)
                    .font(compact ? TypeScale.provenance : TypeScale.label)
                    .foregroundStyle(DesignTokens.cocoa)
                Text(provenance.detail)
                    .font(TypeScale.provenance)
                    .foregroundStyle(DesignTokens.cocoaSoft)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(provenance.label). \(provenance.detail)")
    }
}
