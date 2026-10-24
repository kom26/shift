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
}
