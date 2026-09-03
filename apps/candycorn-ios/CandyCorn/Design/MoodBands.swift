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

enum MoodBandSelection {
    static func value(at x: CGFloat, width: CGFloat) -> Int {
        guard width > 0 else { return 1 }
        let bounded = min(max(x, 0), width)
        if bounded >= width { return 10 }
        return min(max(Int(bounded / width * 10) + 1, 1), 10)
    }

    static func adjusted(_ value: Int?, by delta: Int) -> Int {
        min(max((value ?? 5) + delta, 1), 10)
    }
}

struct MoodBands: View {
    let values: MoodValues
    var compact = false
    var onChange: ((MoodDimension, Int) -> Void)?

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xSmall) {
            band(.anxiety, color: DesignTokens.yellow)
            band(.mood, color: DesignTokens.orange)
            band(.energy, color: DesignTokens.surfaceWarm)
        }
        .frame(maxWidth: .infinity)
        .frame(height: compact && onChange == nil ? 84 : 168)
        .accessibilityElement(children: .contain)
    }

    private func band(_ dimension: MoodDimension, color: Color) -> some View {
        let value = values.value(for: dimension)
        return HStack(spacing: DesignTokens.Spacing.xSmall) {
            if onChange != nil {
                adjustmentButton(dimension, delta: -1, icon: "minus")
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: DesignTokens.moodBandRadius, style: .continuous)
                        .fill(DesignTokens.surface)
                    Rectangle()
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(value ?? 0) / 10)
                    HStack(spacing: DesignTokens.Spacing.small) {
                        Text(dimension.title)
                        Spacer(minLength: DesignTokens.Spacing.small)
                        Text(value.map(String.init) ?? "Not logged")
                            .monospacedDigit()
                            .frame(minWidth: 22, alignment: .trailing)
                    }
                    .font(compact ? TypeScale.provenance : TypeScale.bodyMedium)
                    .foregroundStyle(DesignTokens.cocoa)
                    .padding(.horizontal, compact ? 12 : 16)
                }
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.moodBandRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.moodBandRadius, style: .continuous)
                        .stroke(DesignTokens.hairline, lineWidth: 1)
                )
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { event in
                            onChange?(dimension, MoodBandSelection.value(at: event.location.x, width: geometry.size.width))
                        }
                )
            }
            if onChange != nil {
                adjustmentButton(dimension, delta: 1, icon: "plus")
            }
        }
        .accessibilityElement(children: onChange == nil ? .ignore : .contain)
        .accessibilityLabel(dimension.title)
        .accessibilityValue(value.map { "\($0) out of 10" } ?? "Not logged")
        .accessibilityAdjustableAction { direction in
            guard let onChange else { return }
            let delta = direction == .increment ? 1 : -1
            onChange(dimension, MoodBandSelection.adjusted(value, by: delta))
        }
    }

    private func adjustmentButton(_ dimension: MoodDimension, delta: Int, icon: String) -> some View {
        Button {
            onChange?(dimension, MoodBandSelection.adjusted(values.value(for: dimension), by: delta))
        } label: {
            Image(systemName: icon)
                .frame(width: DesignTokens.controlMinimum, height: DesignTokens.controlMinimum)
        }
        .buttonStyle(.plain)
        .foregroundStyle(DesignTokens.cocoa)
        .accessibilityLabel("\(delta < 0 ? "Decrease" : "Increase") \(dimension.title.lowercased())")
    }
}
