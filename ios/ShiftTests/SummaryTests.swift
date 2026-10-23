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

    @Test func monthPanelSumsPlacedAndAllUnplaced() {
        let store = make()
        let blue = "#0000ff", red = "#ff0000"
        store.save(ev("b1", "2026-10-05", color: blue, allDay: false, st: "09:00", et: "18:00"))
        store.save(ev("b2", "2026-10-06", color: blue, allDay: false, st: "10:00", et: "14:00"))
        store.save(ev("b3", "2026-11-02", color: blue, allDay: false, st: "09:00", et: "18:00"))
        store.save(ev("bu", nil, color: blue, allDay: false, placed: false, st: "15:00", et: "23:00", wh: 7.25))
        store.save(ev("ru", nil, color: red, allDay: false, placed: false, st: "07:00", et: "15:00", wh: 7.25))
        let rows = store.monthPanel(of: "2026-10-15")
        #expect(rows.map(\.color) == [blue, red])
        #expect(rows[0].placed == 12)
        #expect(rows[0].unplaced == 7.25)
        #expect(rows[0].title == "b1")
        #expect(rows[0].id == blue)
        #expect(rows[1].placed == 0)
        #expect(rows[1].unplaced == 7.25)
        #expect(rows[1].title == "ru")
    }

    @Test func monthPanelIgnoresColorFilterAndZeroHours() {
        let store = make()
        store.save(ev("a", "2026-10-05", color: "#0000ff", allDay: false, st: "09:00", et: "13:00"))
        store.save(ev("z", "2026-10-06", color: "#00ff00"))
        store.save(ev("zu", nil, color: "#ff00ff", placed: false))
        store.toggleColor("#ff0000")
        let rows = store.monthPanel(of: "2026-10-15")
        #expect(rows.map(\.color) == ["#0000ff"])
        #expect(rows[0].placed == 4)
    }
}
