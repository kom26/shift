import Foundation
import Testing
@testable import Shift

struct PayCycleTests {
    private func wp(close: Int, pay: Int?, offset: Int) -> Workplace {
        Workplace(id: "w", name: "A", color: "#111111",
                  closingDay: close, paydayDay: pay, paydayMonthOffset: offset)
    }

    @Test func monthEndClosingNextMonthPayday() {
        let w = wp(close: 0, pay: 25, offset: 1)
        let a = PayCycle.period(forPayday: "2026-11-25", workplace: w)
        #expect(a?.start == "2026-10-01")
        #expect(a?.end == "2026-10-31")
        let b = PayCycle.period(forPayday: "2027-01-25", workplace: w)
        #expect(b?.start == "2026-12-01")
        #expect(b?.end == "2026-12-31")
        let c = PayCycle.period(forPayday: "2026-03-25", workplace: w)
        #expect(c?.start == "2026-02-01")
        #expect(c?.end == "2026-02-28")
    }

    @Test func sameMonthPayday() {
        let w = wp(close: 15, pay: 25, offset: 0)
        let p = PayCycle.period(forPayday: "2026-10-25", workplace: w)
        #expect(p?.start == "2026-09-16")
        #expect(p?.end == "2026-10-15")
    }

    @Test func closingDayClampedInFebruary() {
        let w = wp(close: 31, pay: 25, offset: 1)
        let p = PayCycle.period(forPayday: "2026-03-25", workplace: w)
        #expect(p?.end == "2026-02-28")
        #expect(p?.start == "2026-02-01")
        #expect(PayCycle.closeDate(year: 2026, month: 2, closingDay: 31) == "2026-02-28")
        #expect(PayCycle.closeDate(year: 2026, month: 2, closingDay: 0) == "2026-02-28")
        #expect(PayCycle.closeDate(year: 2026, month: 4, closingDay: 15) == "2026-04-15")
    }

    @Test func monthEndPaydayTwoMonthsLater() {
        let w = wp(close: 20, pay: 0, offset: 1)
        let p = PayCycle.period(forPayday: "2026-11-30", workplace: w)
        #expect(p?.start == "2026-09-21")
        #expect(p?.end == "2026-10-20")
    }

    @Test func isPaydayClamps() {
        #expect(PayCycle.isPayday("2026-02-28", workplace: wp(close: 0, pay: 31, offset: 1)))
        #expect(PayCycle.isPayday("2026-02-28", workplace: wp(close: 0, pay: 0, offset: 1)))
        #expect(!PayCycle.isPayday("2026-02-27", workplace: wp(close: 0, pay: 0, offset: 1)))
    }

    @Test func unsetPaydayIsNever() {
        let w = wp(close: 0, pay: nil, offset: 1)
        #expect(!PayCycle.isPayday("2026-11-25", workplace: w))
        #expect(PayCycle.period(forPayday: "2026-11-25", workplace: w) == nil)
    }
}
