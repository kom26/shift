import Foundation
import Testing
@testable import Shift

struct MonthlyPayTests {
    private func make() -> Store {
        let name = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).json")
        let store = Store(fileURL: url, defaults: UserDefaults(suiteName: name)!)
        store.addWorkplace(name: "A", color: "#111111")
        var w = store.workplaces[0]
        w.hourlyWage = 1000
        w.transport = 250
        w.closingDay = 0
        w.paydayDay = 25
        w.paydayMonthOffset = 1
        store.updateWorkplaceDetails(w)
        return store
    }

    private func shift(_ id: String, _ title: String, _ date: String) -> ShiftEvent {
        var e = ev(id, date, allDay: false, st: "09:00", et: "18:00", wh: 8)
        e.title = title
        return e
    }

    private func seeded() -> Store {
        let store = make()
        store.save(shift("e1", "A", "2026-09-05"))
        store.save(shift("e2", "A", "2026-09-20"))
        store.save(shift("e3", "A", "2026-10-05"))
        return store
    }

    @Test func workBasis() {
        let m = seeded().monthlyPay(anchor: "2026-10-15", basis: .work)
        #expect(abs(m.amount - 8500) < 0.0001)
        #expect(m.label == "2026年10月勤務分")
    }

    @Test func paydayBasis() {
        let m = seeded().monthlyPay(anchor: "2026-10-15", basis: .payday)
        #expect(abs(m.amount - 17000) < 0.0001)
        #expect(m.label == "2026年9月勤務分")
    }

    @Test func septemberAnchor() {
        let store = seeded()
        let p = store.monthlyPay(anchor: "2026-09-15", basis: .payday)
        #expect(p.amount == 0)
        #expect(p.label == "2026年8月勤務分")
        let w = store.monthlyPay(anchor: "2026-09-15", basis: .work)
        #expect(abs(w.amount - 17000) < 0.0001)
        #expect(w.label == "2026年9月勤務分")
    }

    @Test func noPaydayWorkplace() {
        let name = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).json")
        let store = Store(fileURL: url, defaults: UserDefaults(suiteName: name)!)
        store.addWorkplace(name: "A", color: "#111111")
        let m = store.monthlyPay(anchor: "2026-10-15", basis: .payday)
        #expect(m.amount == 0)
        #expect(m.label == "給料日なし")
    }

    @Test func workplaceFilterApplies() {
        let store = seeded()
        store.addWorkplace(name: "B", color: "#222222")
        var b = store.workplaces[1]
        b.hourlyWage = 2000
        b.transport = 0
        b.closingDay = 0
        b.paydayDay = 25
        b.paydayMonthOffset = 1
        store.updateWorkplaceDetails(b)
        store.save(shift("b1", "B", "2026-09-10"))
        let all = store.monthlyPay(anchor: "2026-10-15", basis: .payday)
        #expect(abs(all.amount - 33000) < 0.0001)
        store.toggleWorkplaceFilter(store.workplaces[0].id)
        let onlyA = store.monthlyPay(anchor: "2026-10-15", basis: .payday)
        #expect(abs(onlyA.amount - 17000) < 0.0001)
    }
}
