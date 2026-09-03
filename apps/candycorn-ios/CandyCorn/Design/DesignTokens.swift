import SwiftUI

enum DesignTokens {
    static let canvasHex = "#FFFFFF"
    static let surfaceHex = "#FFFFFF"
    static let surfaceWarmHex = "#FFF4E8"
    static let orangeHex = "#F28A3C"
    static let orangePressedHex = "#D9732F"
    static let yellowHex = "#F4C95D"
    static let yellowDeepHex = "#E0AE3A"
    static let cocoaHex = "#2D2825"
    static let cocoaSoftHex = "#766D67"
    static let hairlineHex = "#EBE2D8"
    static let sageHex = "#8FA58B"
    static let roseHex = "#C9877C"
    static let yellowTextHex = "#9A6812"

    static let canvas = Color(hex: canvasHex)
    static let surface = Color(hex: surfaceHex)
    static let surfaceWarm = Color(hex: surfaceWarmHex)
    static let orange = Color(hex: orangeHex)
    static let orangePressed = Color(hex: orangePressedHex)
    static let yellow = Color(hex: yellowHex)
    static let yellowDeep = Color(hex: yellowDeepHex)
    static let cocoa = Color(hex: cocoaHex)
    static let cocoaSoft = Color(hex: cocoaSoftHex)
    static let hairline = Color(hex: hairlineHex)
    static let sage = Color(hex: sageHex)
    static let rose = Color(hex: roseHex)
    static let yellowText = Color(hex: yellowTextHex)

    static let cardRadius: CGFloat = 20
    static let controlRadius: CGFloat = 16
    static let controlMinimum: CGFloat = 44
    static let primaryButtonHeight: CGFloat = 56
    static let screenInset: CGFloat = 16

    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let compact: CGFloat = 12
        static let base: CGFloat = 16
        static let medium: CGFloat = 20
        static let large: CGFloat = 24
        static let xLarge: CGFloat = 32
        static let section: CGFloat = 40
        static let generous: CGFloat = 48
        static let hero: CGFloat = 64
    }

    enum Motion {
        static let fastSeconds = 0.14
        static let baseSeconds = 0.20

        static func animation(reduceMotion: Bool, fast: Bool = false) -> Animation? {
            guard !reduceMotion else { return nil }
            let duration = fast ? fastSeconds : baseSeconds
            return .timingCurve(0.16, 1, 0.3, 1, duration: duration)
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            self = .clear
            return
        }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
