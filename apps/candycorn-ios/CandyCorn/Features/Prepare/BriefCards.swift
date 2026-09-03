import SwiftUI

/// One brief section as a v2 card: icon tile and title, the text, then one provenance line.
struct BriefSectionCard: View {
    let title: String
    let text: AttributedString
    let provenance: Provenance
    var icon: AppIcon = .quote

    init(title: String, text: AttributedString, provenance: Provenance, icon: AppIcon = .quote) {
        self.title = title
        self.text = text
        self.provenance = provenance
        self.icon = icon
    }

    init(title: String, copy: String, provenance: Provenance, icon: AppIcon = .quote) {
        self.init(title: title, text: AttributedString(copy), provenance: provenance, icon: icon)
    }

    var body: some View {
        V2Card {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                HStack(spacing: DesignTokens.Spacing.compact) {
                    IconTile(icon: icon, size: 34)
                    Text(title)
                        .font(TypeScale.cardTitle)
                        .foregroundStyle(DesignTokens.cocoa)
                }
                Text(text)
                    .font(TypeScale.body)
                    .foregroundStyle(DesignTokens.cocoa)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                ProvenanceStack(provenance: provenance)
            }
        }
    }
}
