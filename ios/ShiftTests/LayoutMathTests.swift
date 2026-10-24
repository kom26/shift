import CoreGraphics
import Testing
@testable import Shift

struct LayoutMathTests {
    private func h(_ weeks: Int, _ available: CGFloat) -> CGFloat {
        LayoutMath.monthCalendarHeight(available: available, weeks: weeks)
    }

    @Test func fiveWeeksFitsExactly() { #expect(abs(h(5, 659) - 529) < 0.001) }
    @Test func sixWeeksCappedByBottomArea() { #expect(abs(h(6, 659) - 543) < 0.001) }
    @Test func smallScreenCapped() { #expect(abs(h(5, 400) - 284) < 0.001) }
    @Test func fourWeeks() { #expect(abs(h(4, 800) - 432) < 0.001) }
}
