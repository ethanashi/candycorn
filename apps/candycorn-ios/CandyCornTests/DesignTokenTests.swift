import Foundation
import Testing
@testable import CandyCorn

@Suite("Design tokens")
struct DesignTokenTests {
    @Test("Palette matches the visual contract")
    func palette() {
        #expect(DesignTokens.canvasHex == "#FFFFFF")
        #expect(DesignTokens.surfaceHex == "#FFFFFF")
        #expect(DesignTokens.surfaceWarmHex == "#FFF4E8")
        #expect(DesignTokens.orangeHex == "#F28A3C")
        #expect(DesignTokens.orangePressedHex == "#D9732F")
        #expect(DesignTokens.yellowHex == "#F4C95D")
        #expect(DesignTokens.yellowDeepHex == "#E0AE3A")
        #expect(DesignTokens.cocoaHex == "#2D2825")
        #expect(DesignTokens.cocoaSoftHex == "#5E564F")
        #expect(DesignTokens.hairlineHex == "#EBE2D8")
        #expect(DesignTokens.sageHex == "#8FA58B")
        #expect(DesignTokens.roseHex == "#C9877C")
        #expect(DesignTokens.yellowTextHex == "#9A6812")
    }

    @Test("Geometry protects visual and touch targets")
    func geometry() {
        #expect(DesignTokens.cardRadius == 20)
        #expect(DesignTokens.controlRadius == 16)
        #expect(DesignTokens.controlMinimum == 44)
        #expect(DesignTokens.primaryButtonHeight >= DesignTokens.controlMinimum)
        #expect(DesignTokens.screenInset == 16)
        #expect(DesignTokens.moodBandRadius == 12)
    }

    @Test("Text colors meet WCAG contrast on app surfaces")
    func contrast() {
        for foreground in [DesignTokens.cocoaHex, DesignTokens.cocoaSoftHex] {
            #expect(contrastRatio(foreground, DesignTokens.canvasHex) >= 4.5)
            #expect(contrastRatio(foreground, DesignTokens.surfaceWarmHex) >= 4.5)
        }
        #expect(TypeScale.provenancePointSize == 13)
        #expect(TypeScale.provenanceWeight == 500)
    }

    private func contrastRatio(_ foreground: String, _ background: String) -> Double {
        let light = max(luminance(foreground), luminance(background))
        let dark = min(luminance(foreground), luminance(background))
        return (light + 0.05) / (dark + 0.05)
    }

    private func luminance(_ hex: String) -> Double {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        return [16, 8, 0].map { shift in
            let component = Double((value >> shift) & 0xff) / 255
            return component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }.enumerated().reduce(0) { result, pair in
            result + pair.element * [0.2126, 0.7152, 0.0722][pair.offset]
        }
    }
}
