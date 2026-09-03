import SwiftUI

struct JournalWaveform: View {
    private static let heights: [CGFloat] = [
        22, 46, 64, 38, 76, 31, 58, 82,
        54, 42, 70, 33, 61, 48, 78, 39,
        66, 51, 72, 29, 59, 44, 81, 52,
        68, 35, 63, 47, 75, 40, 57, 71,
    ]

    let phase: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 5
            let count = CGFloat(Self.heights.count)
            let barWidth = max(2, min(4, (proxy.size.width - spacing * (count - 1)) / count))

            HStack(spacing: spacing) {
                ForEach(Array(Self.heights.enumerated()), id: \.offset) { index, height in
                    Capsule(style: .continuous)
                        .fill(DesignTokens.orange)
                        .frame(width: barWidth, height: renderedHeight(height, index: index))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .clipped()
            .animation(DesignTokens.Motion.animation(reduceMotion: reduceMotion), value: phase)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Audio waveform")
    }

    private func renderedHeight(_ percentage: CGFloat, index: Int) -> CGFloat {
        guard !reduceMotion else { return max(16, min(82, percentage)) }
        let adjustment: CGFloat = (index + phase).isMultiple(of: 3) ? 6 : -2
        return max(16, min(88, percentage + adjustment))
    }
}
