import SwiftUI

enum MoodDimension: String, CaseIterable, Sendable {
    case anxiety
    case mood
    case energy

    var title: String { rawValue.capitalized }
}

struct MoodValues: Equatable, Sendable {
    var mood: Int?
    var anxiety: Int?
    var energy: Int?

    func value(for dimension: MoodDimension) -> Int? {
        switch dimension {
        case .anxiety: anxiety
        case .mood: mood
        case .energy: energy
        }
    }
}

struct MoodBands: View {
    let values: MoodValues
    var compact: Bool = false
    var onChange: ((MoodDimension, Int) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            band(.anxiety, color: DesignTokens.yellow)
            band(.mood, color: DesignTokens.orange)
            band(.energy, color: DesignTokens.surfaceWarm)
        }
        .frame(maxWidth: .infinity)
        .frame(height: compact && onChange == nil ? 84 : 168)
        .background(DesignTokens.surface)
        .clipShape(SidewaysKernelShape())
        .overlay(SidewaysKernelShape().stroke(DesignTokens.hairline, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func band(_ dimension: MoodDimension, color: Color) -> some View {
        let value = values.value(for: dimension)
        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                DesignTokens.surface
                color.frame(width: geometry.size.width * CGFloat(value ?? 0) / 10)
                HStack(spacing: DesignTokens.Spacing.small) {
                    Text(dimension.title)
                    Spacer(minLength: DesignTokens.Spacing.small)
                    Text(value.map(String.init) ?? "Not logged")
                        .monospacedDigit()
                }
                .font(compact ? TypeScale.provenance : TypeScale.bodyMedium)
                .foregroundStyle(DesignTokens.cocoa)
                .padding(.horizontal, compact ? 12 : 20)
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { event in
                    guard let onChange, geometry.size.width > 0 else { return }
                    let selected = Int((event.location.x / geometry.size.width * 10).rounded(.up))
                    onChange(dimension, min(max(selected, 1), 10))
                }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dimension.title)
        .accessibilityValue(value.map { "\($0) out of 10" } ?? "Not logged")
        .accessibilityAdjustableAction { direction in
            guard let onChange else { return }
            let current = value ?? 5
            switch direction {
            case .increment: onChange(dimension, min(current + 1, 10))
            case .decrement: onChange(dimension, max(current - 1, 1))
            @unknown default: break
            }
        }
    }
}

private struct SidewaysKernelShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tipX = rect.maxX
        path.move(to: CGPoint(x: rect.minX + rect.height * 0.18, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.height * 0.26, y: rect.minY))
        path.addCurve(to: CGPoint(x: tipX, y: rect.midY), control1: CGPoint(x: rect.maxX - rect.height * 0.1, y: rect.minY), control2: CGPoint(x: tipX, y: rect.height * 0.32))
        path.addCurve(to: CGPoint(x: rect.maxX - rect.height * 0.26, y: rect.maxY), control1: CGPoint(x: tipX, y: rect.height * 0.68), control2: CGPoint(x: rect.maxX - rect.height * 0.1, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.height * 0.18, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.midY), control1: CGPoint(x: rect.minX, y: rect.maxY), control2: CGPoint(x: rect.minX, y: rect.height * 0.68))
        path.addCurve(to: CGPoint(x: rect.minX + rect.height * 0.18, y: rect.minY), control1: CGPoint(x: rect.minX, y: rect.height * 0.32), control2: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
