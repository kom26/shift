import Foundation
import Testing
@testable import Shift

struct DropCheckTests {
    private func timed(_ id: String, _ d: String, _ s: String, _ e: String, allDay: Bool = false) -> ShiftEvent {
        var ev = ShiftEvent.new(on: d)
        ev.id = id
        ev.startDate = d
        ev.endDate = d
        ev.allDay = allDay
        ev.startTime = allDay ? nil : s
        ev.endTime = allDay ? nil : e
        ev.placed = true
        return ev
    }

    @Test func overlapDetected() {
        let a = timed("a", "2026-10-01", "09:00", "12:00")
        let b = timed("b", "2026-10-01", "11:00", "15:00")
        #expect(DropCheck.overlaps(moved: a, others: [b]))
    }

    @Test func touchingEdgesDoNotOverlap() {
        let a = timed("a", "2026-10-01", "09:00", "12:00")
        let b = timed("b", "2026-10-01", "12:00", "15:00")
        #expect(!DropCheck.overlaps(moved: a, others: [b]))
    }

    @Test func allDayAndSelfAreIgnored() {
        let a = timed("a", "2026-10-01", "09:00", "12:00")
        let allDay = timed("c", "2026-10-01", "", "", allDay: true)
        #expect(!DropCheck.overlaps(moved: a, others: [allDay, a]))
        #expect(!DropCheck.overlaps(moved: allDay, others: [a]))
    }

    @Test func overnightEventOverlapsNextMorning() {
        let night = timed("n", "2026-10-01", "22:00", "06:00")
        var nightFixed = night
        nightFixed.endDate = "2026-10-02"
        let morning = timed("m", "2026-10-02", "05:00", "08:00")
        #expect(DropCheck.overlaps(moved: nightFixed, others: [morning]))
    }
}
