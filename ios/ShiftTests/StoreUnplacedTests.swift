import Foundation
import Testing
@testable import Shift

struct StoreUnplacedTests {
    private func make() -> Store {
        let name = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).json")
        return Store(fileURL: url, defaults: UserDefaults(suiteName: name)!)
    }

    @Test func daysBetween() {
        #expect(Rules.daysBetween("2026-10-20", "2026-10-22") == 2)
        #expect(Rules.daysBetween("2026-10-30", "2026-11-02") == 3)
        #expect(Rules.daysBetween("2026-10-20", "2026-10-20") == 0)
    }

    @Test func placeUnplacedEventSetsDatesAndPlaced() {
        let store = make()
        store.save(ev("u", nil, placed: false))
        store.place(id: "u", on: "2026-10-24")
        let e = store.events[0]
        #expect(e.placed)
        #expect(e.startDate == "2026-10-24")
        #expect(e.endDate == "2026-10-24")
    }

    @Test func placeKeepsMultiDayDuration() {
        let store = make()
        store.save(ev("a", "2026-10-20", "2026-10-22"))
        store.place(id: "a", on: "2026-10-25")
        #expect(store.events[0].startDate == "2026-10-25")
        #expect(store.events[0].endDate == "2026-10-27")
    }

    @Test func placeOvernightEventEndsNextDay() {
        let store = make()
        store.save(ev("u", nil, placed: false, allDay: false, st: "22:00", et: "06:00"))
        store.place(id: "u", on: "2026-10-24")
        #expect(store.events[0].endDate == "2026-10-25")
    }

    @Test func placeUnknownIdIsIgnored() {
        let store = make()
        store.save(ev("a", "2026-10-20"))
        store.place(id: "nope", on: "2026-10-24")
        #expect(store.events.map(\.id) == ["a"])
        #expect(store.events[0].startDate == "2026-10-20")
    }

    @Test func unplaceClearsDatesAndMovesToEndOfUnplaced() {
        let store = make()
        store.save(ev("a", "2026-10-20"))
        store.save(ev("u1", nil, placed: false))
        store.save(ev("b", "2026-10-21"))
        store.unplace(id: "a")
        #expect(store.events.map(\.id) == ["b", "u1", "a"])
        let a = store.events[2]
        #expect(!a.placed)
        #expect(a.startDate == nil)
        #expect(a.endDate == nil)
        #expect(store.unplacedEvents.map(\.id) == ["u1", "a"])
    }

    @Test func sortUnplacedOrdersByStartTimeThenHoursWithAllDayLast() {
        let store = make()
        store.save(ev("p", "2026-10-20"))
        store.save(ev("a", nil, placed: false))
        store.save(ev("b", nil, placed: false, allDay: false, st: "15:00", et: "23:00"))
        store.save(ev("c", nil, placed: false, allDay: false, st: "07:00", et: "15:00"))
        store.save(ev("d", nil, placed: false, allDay: false, st: "15:00", et: "19:00"))
        store.sortUnplaced()
        #expect(store.events.map(\.id) == ["p", "c", "d", "b", "a"])
    }

    @Test func recallMonthMovesOnlyThatMonthAndSorts() {
        let store = make()
        store.save(ev("x", "2026-10-10", allDay: false, st: "09:00", et: "18:00"))
        store.save(ev("y", "2026-11-02"))
        store.save(ev("u", nil, placed: false, allDay: false, st: "20:00", et: "23:00"))
        let n = store.recallMonth(of: "2026-10-15")
        #expect(n == 1)
        #expect(store.events.map(\.id) == ["y", "x", "u"])
        #expect(store.events[1].placed == false)
        #expect(store.events[1].startDate == nil)
    }

    @Test func recallMonthWithNothingToRecallReturnsZero() {
        let store = make()
        store.save(ev("y", "2026-11-02"))
        #expect(store.recallMonth(of: "2026-10-15") == 0)
        #expect(store.events.map(\.id) == ["y"])
    }

    @Test func unplacedChangesPersist() {
        let name = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).json")
        let defaults = UserDefaults(suiteName: name)!
        let store = Store(fileURL: url, defaults: defaults)
        store.save(ev("a", "2026-10-20"))
        store.unplace(id: "a")
        let reloaded = Store(fileURL: url, defaults: defaults)
        #expect(reloaded.events[0].placed == false)
    }
}
