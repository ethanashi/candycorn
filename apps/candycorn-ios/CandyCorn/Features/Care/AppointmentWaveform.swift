import SwiftUI

struct AppointmentWaveform: View {
    private static let bars = [36, 62, 45, 78, 52, 30, 68, 84, 41, 57, 72, 35, 64, 48, 80, 39, 59, 74, 43, 67, 32, 76, 51, 88, 46, 63, 38, 70, 54, 82, 42, 61]

    let level: Float
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(Self.bars.enumerated()), id: \.offset) { _, height in
                Capsule()
                    .fill(DesignTokens.orange)
                    .frame(width: 4, height: barHeight(height))
                    .frame(maxHeight: .infinity)
                    .animation(DesignTokens.Motion.animation(reduceMotion: reduceMotion), value: level)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 116)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Appointment waveform")
    }

    private func barHeight(_ percentage: Int) -> CGFloat {
        let bounded = min(max(percentage, 16), 100)
        let normalized = min(max(CGFloat(level), 0), 1)
        return max(12, CGFloat(bounded) * 1.16 * (0.25 + normalized * 0.75))
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
