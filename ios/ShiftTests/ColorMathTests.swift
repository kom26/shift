import Testing
@testable import Shift

struct ColorMathTests {
    @Test func visibleLightensTowardWhite() {
        #expect(ColorMath.visible("#000000") == "#b3b3b3")
        #expect(ColorMath.visible("#ffffff") == "#ffffff")
    }

    @Test func roundTripIsStableForPastels() {
        for base in Store.defaultColors {
            let again = ColorMath.base(fromVisible: ColorMath.visible(base))
            let a = base.dropFirst(), b = again.dropFirst()
            for i in stride(from: 0, to: 6, by: 2) {
                let x = Int(a.dropFirst(i).prefix(2), radix: 16) ?? 0
                let y = Int(b.dropFirst(i).prefix(2), radix: 16) ?? 0
                #expect(abs(x - y) <= 3)
            }
        }
    }

    @Test func tooDarkVisibleClampsToZero() {
        #expect(ColorMath.base(fromVisible: "#000000") == "#000000")
    }

    @Test func closeColorsAreTheSameButOtherColorsAreNot() {
        // 色空間の変換でずれた同じ色は「同じ」とみなし、別の色(暗い色など)は「別」とみなす
        #expect(ColorMath.isClose("#8d8df2", "#8e8cf1"))
        #expect(!ColorMath.isClose("#8d8df2", "#000000"))
        #expect(!ColorMath.isClose("#8d8df2", "#8d8df8"))
    }
}
