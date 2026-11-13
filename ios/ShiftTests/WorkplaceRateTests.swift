import Foundation
import Testing
@testable import Shift

struct WorkplaceRateTests {
    private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.0001 }

    private func rate(_ from: String, _ wage: Int, transport: Int = 0, sunday: Int = 0) -> PayRate {
        var bonus = [0, 0, 0, 0, 0, 0, 0]
        bonus[0] = sunday
        return PayRate(from: from, hourlyWage: wage, transport: transport, weekdayBonus: bonus, holidayBonus: 0)
    }

    private func wp() -> Workplace {
        Workplace(id: "w", name: "A", color: "#111111", hourlyWage: 1000, transport: 100,
                  rateChanges: [rate("2026-10-01", 1100, transport: 200), rate("2027-04-01", 1200, transport: 200, sunday: 50)])
    }

    @Test func rateIsPickedByStartDate() {
        let w = wp()
        #expect(w.rate(on: "2026-09-30").hourlyWage == 1000)
        #expect(w.rate(on: "2026-10-01").hourlyWage == 1100)
        #expect(w.rate(on: "2027-03-31").hourlyWage == 1100)
        #expect(w.rate(on: "2027-04-01").hourlyWage == 1200)
        #expect(w.resolved(on: "2026-10-15").transport == 200)
        #expect(w.resolved(on: "2026-09-15").transport == 100)
    }

    @Test func payUsesRateOfStartDate() throws {
        let w = wp()
        let before = ev("a", "2026-09-29", "2026-09-29", allDay: false, st: "09:00", et: "17:00", wh: 8)
        let after = ev("b", "2026-10-06", "2026-10-06", allDay: false, st: "09:00", et: "17:00", wh: 8)
        let p1 = try #require(PayCalculator.pay(event: before, workplace: w, isHoliday: false))
        let p2 = try #require(PayCalculator.pay(event: after, workplace: w, isHoliday: false))
        #expect(close(p1.total, 8000 + 200))
        #expect(close(p2.total, 8800 + 400))
    }

    @Test func overnightShiftUsesStartDate() throws {
        let w = wp()
        // 9/30 22:00 → 10/1 6:00 は、開始日(9/30)の時給
        let e = ev("n", "2026-09-30", "2026-10-01", allDay: false, st: "22:00", et: "06:00", wh: 8)
        let p = try #require(PayCalculator.pay(event: e, workplace: w, isHoliday: false))
        #expect(close(p.base, 8000))
    }

    @Test func noChangesKeepsOldBehavior() {
        let w = Workplace(id: "w", name: "A", color: "#111", hourlyWage: 1000)
        #expect(w.resolved(on: "2030-01-01") == w)
        #expect(w.payRates.count == 1)
    }

    @Test func payRatesRoundTrip() {
        var w = wp()
        var rates = w.payRates
        #expect(rates.map(\.from) == ["", "2026-10-01", "2027-04-01"])
        rates[0].hourlyWage = 950
        rates.remove(at: 2)
        w.payRates = rates
        #expect(w.hourlyWage == 950)
        #expect(w.rateChanges.map(\.from) == ["2026-10-01"])
    }

    @Test func upsertReplacesSameDate() {
        let a = wp().payRates
        let r = rate("2026-10-01", 1150)
        let out = PayRate.upsert(r, into: a)
        #expect(out.count == 3)
        #expect(out[1].hourlyWage == 1150)
        let added = PayRate.upsert(rate("2026-12-01", 1130), into: a)
        #expect(added.map(\.from) == ["", "2026-10-01", "2026-12-01", "2027-04-01"])
    }

    @Test func codableKeepsChangesAndOldJSONHasNone() throws {
        let w = wp()
        let back = try JSONDecoder().decode(Workplace.self, from: JSONEncoder().encode(w))
        #expect(back == w)
        let old = ##"{"id":"w","name":"A","color":"#111","hourlyWage":1000}"##
        let o = try JSONDecoder().decode(Workplace.self, from: Data(old.utf8))
        #expect(o.rateChanges.isEmpty)
    }

    @Test func insertEarlierMovesBaseAfterEnd() {
        // 最初 1,100円 だけのところに、9/30 までは 1,050円 だったと入れる
        let a = Workplace(id: "w", name: "A", color: "#111", hourlyWage: 1100).payRates
        let out = PayRate.insertEarlier(rate("2026-09-30", 1050), endingOn: "2026-09-30", into: a)
        #expect(out.map(\.from) == ["", "2026-10-01"])
        #expect(out.map(\.hourlyWage) == [1050, 1100])
        #expect(out[0].id == "base")
    }

    @Test func insertEarlierRightBeforeNextChangeReplacesBase() {
        // 最初 1,000円、10/1 から 1,100円。9/30 までは 1,050円 だった → 最初の 1,000円 は使われなくなる
        let a = wp().payRates
        let out = PayRate.insertEarlier(rate("2026-09-30", 1050), endingOn: "2026-09-30", into: a)
        #expect(out.map(\.from) == ["", "2026-10-01", "2027-04-01"])
        #expect(out.map(\.hourlyWage) == [1050, 1100, 1200])
    }

    @Test func insertEarlierWellBeforeNextChangeKeepsBaseInBetween() {
        let a = wp().payRates
        let out = PayRate.insertEarlier(rate("2026-03-31", 950), endingOn: "2026-03-31", into: a)
        #expect(out.map(\.from) == ["", "2026-04-01", "2026-10-01", "2027-04-01"])
        #expect(out.map(\.hourlyWage) == [950, 1000, 1100, 1200])
    }

    @Test func summaries() {
        #expect(WorkplaceSummary.bonus(weekday: [100, 0, 0, 0, 0, 0, 100], holiday: 150) == "土日 +100円/時 ・ 祝日 +150円/時")
        #expect(WorkplaceSummary.bonus(weekday: [0, 50, 50, 50, 50, 50, 0], holiday: 0) == "平日 +50円/時")
        #expect(WorkplaceSummary.bonus(weekday: [0, 0, 0, 0, 0, 0, 0], holiday: 0) == "なし")
        #expect(WorkplaceSummary.bonus(weekday: [0, 30, 0, 30, 0, 0, 0], holiday: 0) == "月水 +30円/時")
        #expect(WorkplaceSummary.payday(isDaily: false, dailyMonthly: false, closingDay: 0, paydayDay: 25, offset: 1) == "末日締め・翌月25日払い")
        #expect(WorkplaceSummary.payday(isDaily: false, dailyMonthly: false, closingDay: 15, paydayDay: nil, offset: 1) == "15日締め")
        #expect(WorkplaceSummary.payday(isDaily: true, dailyMonthly: false, closingDay: 0, paydayDay: nil, offset: 1) == "日払い")
        #expect(WorkplaceSummary.date("2027-04-01") == "2027年4月1日")
        #expect(WorkplaceSummary.yen(1150) == "1,150円")
    }
}
