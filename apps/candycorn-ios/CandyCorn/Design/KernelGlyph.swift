import SwiftUI

struct KernelGlyph: View {
    let voice: ProvenanceVoice
    var height: CGFloat = 18
    var decorative: Bool = true

    var body: some View {
        KernelShape()
            .fill(color)
            .frame(width: height / 1.3, height: height)
            .accessibilityHidden(decorative)
            .accessibilityLabel(decorative ? "" : accessibilityLabel)
    }

    private var color: Color {
        switch voice {
        case .user: DesignTokens.orange
        case .provider: DesignTokens.cocoa
        case .candyCorn: DesignTokens.yellow
        }
    }

    private var accessibilityLabel: String {
        switch voice {
        case .user: "You"
        case .provider: "Provider"
        case .candyCorn: "Candy Corn suggestion"
        }
    }
}

private struct KernelShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        path.move(to: CGPoint(x: midX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY * 0.72),
            control1: CGPoint(x: rect.maxX * 0.76, y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: rect.maxY * 0.44)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY * 0.72),
            control1: CGPoint(x: rect.maxX, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: midX, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.maxY * 0.44),
            control2: CGPoint(x: rect.maxX * 0.24, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
