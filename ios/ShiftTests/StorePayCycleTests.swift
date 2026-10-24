import Foundation
import Testing
@testable import Shift

struct StorePayCycleTests {
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

    @Test func paymentsSumPeriodEvents() {
        let store = make()
        store.save(shift("e1", "A", "2026-10-05"))
        store.save(shift("e2", "A", "2026-10-20"))
        store.save(shift("e3", "A", "2026-11-02"))
        let rows = store.payments(onPayday: "2026-11-25")
        #expect(rows.count == 1)
        #expect(abs(rows[0].amount - 17000) < 0.0001)
        #expect(rows[0].start == "2026-10-01")
        #expect(rows[0].end == "2026-10-31")
        #expect(store.payments(onPayday: "2026-11-24").isEmpty)
        #expect(store.hasPayday(on: "2026-11-25"))
        #expect(!store.hasPayday(on: "2026-11-24"))
    }

    @Test func workplaceWithoutPaydayNeverAppears() {
        let store = make()
        store.addWorkplace(name: "B", color: "#222222")
        let rows = store.payments(onPayday: "2026-11-25")
        #expect(rows.count == 1)
        #expect(rows[0].workplace.name == "A")
    }

    @Test func otherWorkplaceEventsNotCounted() {
        let store = make()
        store.addWorkplace(name: "B", color: "#222222")
        store.save(shift("e1", "A", "2026-10-05"))
        var b = shift("e2", "B", "2026-10-06")
        b.workplaceId = store.workplaces[1].id
        store.save(b)
        let rows = store.payments(onPayday: "2026-11-25")
        #expect(rows.count == 1)
        #expect(abs(rows[0].amount - 8500) < 0.0001)
    }

    @Test func emptyPeriodGivesZero() {
        let store = make()
        let rows = store.payments(onPayday: "2026-11-25")
        #expect(rows.count == 1)
        #expect(rows[0].amount == 0)
    }
}
