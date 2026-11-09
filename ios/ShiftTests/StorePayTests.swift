import Foundation
import Testing
@testable import Shift

struct StorePayTests {
    private func make(holidayBonus: Int = 0) -> Store {
        let name = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).json")
        let store = Store(fileURL: url, defaults: UserDefaults(suiteName: name)!)
        store.addWorkplace(name: "A", color: "#111111")
        var w = store.workplaces[0]
        w.hourlyWage = 1000
        w.transport = 250
        w.holidayBonus = holidayBonus
        store.updateWorkplaceDetails(w)
        return store
    }

    private func shift(_ id: String, _ title: String, _ date: String) -> ShiftEvent {
        var e = ev(id, date, allDay: false, st: "09:00", et: "18:00", wh: 8)
        e.title = title
        return e
    }

    @Test func oneWayTransportIsDoubledInStorePay() {
        let store = make()
        store.save(bind(store, shift("e1", "A", "2026-10-20")))
        let t = store.totals(from: "2026-10-18", to: "2026-10-24")
        #expect(abs(t[0].pay - 8500) < 0.0001)
    }

    @Test func totalsIncludePay() {
        let store = make()
        store.save(bind(store, shift("e1", "A", "2026-10-20")))
        store.save(bind(store, shift("e2", "A", "2026-10-21")))
        let t = store.totals(from: "2026-10-18", to: "2026-10-24")
        #expect(t.count == 1)
        #expect(abs(t[0].pay - 17000) < 0.0001)
        #expect(t[0].count == 2)
    }

    @Test func eventWithoutWorkplaceAddsNoPay() {
        let store = make()
        store.save(bind(store, shift("e1", "A", "2026-10-20")))
        store.save(bind(store, shift("e2", "B", "2026-10-21")))
        let t = store.totals(from: "2026-10-18", to: "2026-10-24")
        #expect(t.count == 1)
        let a = t.first { $0.title == "A" }
        let other = t.first { $0.title != "A" }
        #expect(abs((a?.pay ?? -1) - 8500) < 0.0001)
        #expect(a?.count == 1)
        #expect(other == nil)
    }

    @Test func workplaceIdTakesPriorityOverTitle() {
        let store = make()
        var e = shift("e1", "something", "2026-10-20")
        e.workplaceId = store.workplaces[0].id
        #expect(store.workplace(for: e)?.name == "A")
        #expect(store.workplace(for: shift("e2", "A", "2026-10-20"))?.name == "A")
        #expect(store.workplace(for: shift("e3", "Z", "2026-10-20")) == nil)
    }

    @Test func holidayClosureAppliesBonus() {
        let store = make(holidayBonus: 100)
        store.save(bind(store, shift("e1", "A", "2026-10-20")))
        let t = store.totals(from: "2026-10-20", to: "2026-10-20", isHoliday: { $0 == "2026-10-20" })
        #expect(abs(t[0].pay - 9300) < 0.0001)
    }

    @Test func addWorkplaceWithDetails() {
        let store = make()
        store.addWorkplace(Workplace(id: "n1", name: "B", color: "#222222", hourlyWage: 1200))
        #expect(store.workplaces.last?.hourlyWage == 1200)
    }

    @Test func hoursWithoutSavedWorkHoursUseTheWorkplaceBreakRules() {
        let store = make()
        var w = store.workplaces[0]
        w.breakRules = [BreakRule(id: "r1", hours: 6, comparison: .over, minutes: 30)]
        store.updateWorkplaceDetails(w)
        var e = ev("e1", "2026-10-20", allDay: false, st: "22:00", et: "06:30")
        e.workplaceId = w.id
        e.endDate = "2026-10-21"
        // 拘束 8.5 時間。職場の休憩ルール(6 時間超で 30 分)なら 8 時間。法定の 60 分なら 7.5 時間
        #expect(store.effectiveHours(of: e) == 8)
    }
}
