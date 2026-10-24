import Foundation
import Testing
@testable import Shift

struct SummaryTests {
    private func make() -> Store {
        let name = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).json")
        return Store(fileURL: url, defaults: UserDefaults(suiteName: name)!)
    }

    @Test func totalsCarryFirstTitlePerColor() {
        let store = make()
        store.save(ev("first", "2026-10-05", color: "#111111", allDay: false, st: "09:00", et: "13:00"))
        store.save(ev("second", "2026-10-06", color: "#111111", allDay: false, st: "09:00", et: "13:00"))
        let t = store.totals(from: "2026-10-01", to: "2026-10-31")
        #expect(t.count == 1)
        #expect(t[0].title == "first")
        #expect(t[0].count == 2)
    }
    @Test func totalsSortedByHoursDescending() {
        let store = make()
        store.save(ev("a", "2026-10-05", color: "#aaaaaa", allDay: false, st: "09:00", et: "14:00", wh: 4))
        store.save(ev("b", "2026-10-06", color: "#bbbbbb", allDay: false, st: "09:00", et: "18:00", wh: 8))
        let t = store.totals(from: "2026-10-01", to: "2026-10-31")
        #expect(t.map(\.color) == ["#bbbbbb", "#aaaaaa"])
    }

    @Test func totalsFollowOrderByThenHours() {
        let store = make()
        store.save(ev("a", "2026-10-05", color: "#aaaaaa", allDay: false, st: "09:00", et: "14:00", wh: 4))
        store.save(ev("b", "2026-10-06", color: "#bbbbbb", allDay: false, st: "09:00", et: "10:00", wh: 1))
        let t = store.totals(from: "2026-10-04", to: "2026-10-10", orderBy: ["#bbbbbb", "#aaaaaa"])
        #expect(t.map(\.color) == ["#bbbbbb", "#aaaaaa"])
        store.save(ev("c", "2026-10-07", color: "#cccccc", allDay: false, st: "09:00", et: "20:00", wh: 10))
        let t2 = store.totals(from: "2026-10-04", to: "2026-10-10", orderBy: ["#bbbbbb", "#aaaaaa"])
        #expect(t2.map(\.color) == ["#bbbbbb", "#aaaaaa", "#cccccc"])
    }
}
