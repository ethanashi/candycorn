import SwiftUI

struct AppointmentWaveform: View {
    // Exact silhouette from the accepted recording frame in design/sheet.html.
    private static let bars = [
        22, 38, 64, 44, 78, 52, 26, 58, 94, 62, 38, 72,
        42, 88, 52, 30, 68, 48, 82, 34, 58, 92, 46, 72,
        28, 62, 40, 76, 48, 24, 54, 84, 44, 66, 32, 74,
        38, 58, 88, 50, 30, 68, 46, 78, 36, 60, 26, 72,
    ]

    let level: Float
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(Self.bars.enumerated()), id: \.offset) { _, height in
                Capsule()
                    .fill(DesignTokens.orange)
                    .frame(width: 4, height: barHeight(height))
                    .frame(maxHeight: .infinity)
                    .animation(DesignTokens.Motion.animation(reduceMotion: reduceMotion), value: level)
            }
        }
        .frame(maxWidth: 358)
        .frame(height: 116)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Appointment waveform")
    }

    private func barHeight(_ percentage: Int) -> CGFloat {
        let bounded = min(max(percentage, 16), 100)
        let normalized = min(max(CGFloat(level), 0), 1)
        return max(12, CGFloat(bounded) * (0.42 + normalized * 0.58))
    }
}

struct AppointmentRecordingClock: Equatable, Sendable {
    static let initialSeconds = 18 * 60 + 24
    private(set) var elapsedSeconds: Int
    private(set) var isRunning: Bool

    init(elapsedSeconds: Int = Self.initialSeconds, isRunning: Bool = true) {
        self.elapsedSeconds = max(0, elapsedSeconds)
        self.isRunning = isRunning
    }

    mutating func tick() {
        guard isRunning, elapsedSeconds < 86_400 else { return }
        elapsedSeconds += 1
    }

    @discardableResult
    mutating func finish() -> Bool {
        guard isRunning else { return false }
        isRunning = false
        return true
    }

    mutating func cancel() {
        isRunning = false
    }

    static func format(seconds: Int) -> String {
        guard seconds >= 0 else { return "00:00" }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    static func format(milliseconds: Int) -> String {
        guard milliseconds >= 0 else { return "0:00" }
        let seconds = milliseconds / 1_000
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
