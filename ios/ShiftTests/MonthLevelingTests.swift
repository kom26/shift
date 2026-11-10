import CoreGraphics
import Testing
@testable import Shift

struct MonthLevelingTests {
    private func heights(_ need: [CGFloat], _ avail: CGFloat) -> [CGFloat] {
        let level = MonthView.levelingHeight(need, avail: avail)
        return need.map { max($0, level) }
    }

    @Test func weeksThatFitAreAllTheSameHeight() {
        // 予定のある週も、ない週も、入りきるなら同じ高さ
        let h = heights([40, 52, 40, 40, 40], 250)
        #expect(h.allSatisfy { abs($0 - 50) < 0.01 || $0 == 52 } == false)
        #expect(h.allSatisfy { abs($0 - 50) < 0.01 })
    }

    @Test func onlyTheWeekThatNeedsMoreGrows() {
        let h = heights([40, 90, 40], 200)
        #expect(abs(h[0] - 55) < 0.01)
        #expect(abs(h[2] - 55) < 0.01)
        #expect(h[1] == 90)
        #expect(abs(h.reduce(0, +) - 200) < 0.01)
    }

    @Test func noLevelingWhenNothingIsLeft() {
        #expect(MonthView.levelingHeight([100, 100], avail: 200) == 0)
        #expect(MonthView.levelingHeight([120, 100], avail: 200) == 0)
    }
}
