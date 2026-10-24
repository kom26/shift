import Testing
@testable import Shift

struct PayCalculatorTests {
    private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.0001 }

    private func wp(holiday: Int = 0, sunday: Int = 0, fromNight: Bool = true) -> Workplace {
        var bonus = [0, 0, 0, 0, 0, 0, 0]
        bonus[0] = sunday
        return Workplace(id: "w1", name: "A", color: "#111111", hourlyWage: 1000, transport: 500,
                         weekdayBonus: bonus, holidayBonus: holiday, breakRules: [], breakFromNight: fromNight)
    }

    private func timed(_ date: String, _ st: String, _ et: String) -> ShiftEvent {
        ev("x", date, date, allDay: false, st: st, et: et)
    }

    @Test func daytime() throws {
        let p = try #require(PayCalculator.pay(event: timed("2026-10-20", "09:00", "18:00"), workplace: wp(), isHoliday: false))
        #expect(close(p.base, 8000))
        #expect(close(p.night, 0))
        #expect(close(p.overtime, 0))
        #expect(close(p.bonus, 0))
        #expect(close(p.transport, 500))
        #expect(close(p.total, 8500))
        #expect(p.netMinutes == 480)
    }

    @Test func nightBreakFromNight() throws {
        let p = try #require(PayCalculator.pay(event: timed("2026-10-20", "22:00", "06:00"), workplace: wp(), isHoliday: false))
        #expect(p.nightMinutes == 375)
        #expect(p.netMinutes == 435)
        #expect(close(p.base, 7250))
        #expect(close(p.night, 1562.5))
        #expect(close(p.total, 9312.5))
    }

    @Test func nightBreakFromDay() throws {
        var e = timed("2026-10-20", "22:00", "06:00")
        e.breakInNight = false
        let p = try #require(PayCalculator.pay(event: e, workplace: wp(), isHoliday: false))
        #expect(p.nightMinutes == 420)
        #expect(close(p.base, 7250))
        #expect(close(p.night, 1750))
        #expect(close(p.total, 9500))
    }

    @Test func eventOverridesWorkplaceDefault() throws {
        var e = timed("2026-10-20", "22:00", "06:00")
        e.breakInNight = true
        let p = try #require(PayCalculator.pay(event: e, workplace: wp(fromNight: false), isHoliday: false))
        #expect(p.nightMinutes == 375)
    }

    @Test func overtime() throws {
        let p = try #require(PayCalculator.pay(event: timed("2026-10-20", "09:00", "20:00"), workplace: wp(), isHoliday: false))
        #expect(p.netMinutes == 600)
        #expect(p.overtimeMinutes == 120)
        #expect(close(p.base, 10000))
        #expect(close(p.overtime, 500))
        #expect(close(p.total, 11000))
    }

    @Test func holidayBonus() throws {
        let p = try #require(PayCalculator.pay(event: timed("2026-10-20", "09:00", "18:00"), workplace: wp(holiday: 100), isHoliday: true))
        #expect(close(p.bonus, 800))
    }

    @Test func holidayOverridesSunday() throws {
        // 2026-10-25 は日曜
        let e = timed("2026-10-25", "09:00", "18:00")
        let h = try #require(PayCalculator.pay(event: e, workplace: wp(holiday: 100, sunday: 50), isHoliday: true))
        #expect(close(h.bonus, 800))
        let s = try #require(PayCalculator.pay(event: e, workplace: wp(holiday: 100, sunday: 50), isHoliday: false))
        #expect(close(s.bonus, 400))
    }

    @Test func allDayIsNil() {
        #expect(PayCalculator.pay(event: ev("x", "2026-10-20"), workplace: wp(), isHoliday: false) == nil)
    }

    @Test func missingTimesIsNil() {
        let e = ev("x", "2026-10-20", allDay: false)
        #expect(PayCalculator.pay(event: e, workplace: wp(), isHoliday: false) == nil)
    }

    @Test func zeroNetIsNil() {
        let e = ev("x", "2026-10-20", allDay: false, st: "09:00", et: "18:00", wh: 0)
        #expect(PayCalculator.pay(event: e, workplace: wp(), isHoliday: false) == nil)
    }
}
