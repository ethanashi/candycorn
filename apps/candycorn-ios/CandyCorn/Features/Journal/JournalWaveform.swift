import SwiftUI

struct JournalWaveform: View {
    private static let heights: [CGFloat] = [
        22, 46, 64, 38, 76, 31, 58, 82,
        54, 42, 70, 33, 61, 48, 78, 39,
        66, 51, 72, 29, 59, 44, 81, 52,
        68, 35, 63, 47, 75, 40, 57, 71,
    ]

    let level: Float
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 5
            let count = CGFloat(Self.heights.count)
            let barWidth = max(2, min(4, (proxy.size.width - spacing * (count - 1)) / count))

            HStack(spacing: spacing) {
                ForEach(Array(Self.heights.enumerated()), id: \.offset) { _, height in
                    Capsule(style: .continuous)
                        .fill(DesignTokens.orange)
                        .frame(width: barWidth, height: renderedHeight(height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .clipped()
            .animation(DesignTokens.Motion.animation(reduceMotion: reduceMotion), value: level)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Audio waveform")
    }

    private func renderedHeight(_ percentage: CGFloat) -> CGFloat {
        let normalized = min(max(CGFloat(level), 0), 1)
        return max(8, min(88, percentage * (0.25 + normalized * 0.75)))
    }
}
