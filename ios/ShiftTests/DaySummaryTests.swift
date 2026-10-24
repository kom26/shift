import Foundation
import Testing
@testable import Shift

struct DaySummaryTests {
    private func make() -> Store {
        let name = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).json")
        return Store(fileURL: url, defaults: UserDefaults(suiteName: name)!)
    }

    @Test func ordering() {
        let store = make()
        store.save(ev("a", "2026-10-01", allDay: false, st: "18:00", et: "23:00"))
        store.save(ev("b", "2026-10-01", allDay: false, st: "09:00", et: "12:00"))
        store.save(ev("c", "2026-10-01"))
        #expect(store.daySummary(date: "2026-10-01").events.map(\.event.id) == ["c", "b", "a"])
    }

    @Test func overnight() {
        let store = make()
        store.save(ev("n", "2026-10-01", "2026-10-02", allDay: false, st: "22:00", et: "06:30"))
        let d1 = store.daySummary(date: "2026-10-01").events
        let d2 = store.daySummary(date: "2026-10-02").events
        #expect(d1.count == 1 && !d1[0].isContinuation)
        #expect(d2.count == 1 && d2[0].isContinuation)
        #expect(store.daySummary(date: "2026-10-03").events.isEmpty)
    }

    @Test func extendedTime() {
        let store = make()
        store.save(ev("x", "2026-10-01", allDay: false, st: "29:00", et: "36:00"))
        #expect(store.daySummary(date: "2026-10-01").events.isEmpty)
        let d2 = store.daySummary(date: "2026-10-02").events
        #expect(d2.count == 1 && d2[0].isContinuation)
    }

    @Test func unplacedExcluded() {
        let store = make()
        store.save(ev("u", "2026-10-01", placed: false))
        #expect(store.daySummary(date: "2026-10-01").events.isEmpty)
    }

    @Test func paydays() {
        let store = make()
        store.addWorkplace(name: "A", color: "#111111")
        var w = store.workplaces[0]
        w.hourlyWage = 1000
        w.transport = 500
        w.closingDay = 0
        w.paydayDay = 25
        w.paydayMonthOffset = 1
        store.updateWorkplaceDetails(w)
        var e = ev("e1", "2026-09-05", allDay: false, st: "09:00", et: "18:00", wh: 8)
        e.title = "A"
        store.save(e)
        let rows = store.daySummary(date: "2026-10-25").paydays
        #expect(rows.count == 1)
        #expect(abs(rows[0].amount - 8500) < 0.0001)
        #expect(store.daySummary(date: "2026-10-24").paydays.isEmpty)
    }
}
