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
        #expect(DesignTokens.cocoaSoftHex == "#766D67")
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
    }
}
