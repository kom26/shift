import Foundation
import Testing
@testable import Shift

/// 共有カレンダーで、24時をこえる予定の見え方を変える(この端末だけ)
struct OvernightDisplayTests {
    private func timed(_ start: String, _ end: String, _ st: String, _ et: String) -> ShiftEvent {
        ev("e", start, end, allDay: false, st: st, et: et)
    }

    private func shape(_ e: ShiftEvent) -> [String?] { [e.startDate, e.startTime, e.endDate, e.endTime] }

    @Test func defaultKeepsTheEventAsIs() {
        let e = timed("2026-11-03", "2026-11-03", "22:00", "30:00")
        #expect(OvernightDisplay().apply(e) == e)
    }

    @Test func lateEndCrossAndFit() {
        let fit = timed("2026-11-03", "2026-11-03", "22:00", "30:00")
        let cross = timed("2026-11-03", "2026-11-04", "22:00", "06:00")
        #expect(shape(OvernightDisplay(lateEnd: .cross).apply(fit)) == ["2026-11-03", "22:00", "2026-11-04", "06:00"])
        #expect(shape(OvernightDisplay(lateEnd: .fit).apply(cross)) == ["2026-11-03", "22:00", "2026-11-03", "30:00"])
        // 24時をこえない予定は、そのまま
        let day = timed("2026-11-03", "2026-11-03", "09:00", "17:00")
        #expect(OvernightDisplay(lateEnd: .cross).apply(day) == day)
    }

    @Test func afterMidnightChoices() {
        let keep = timed("2026-11-03", "2026-11-03", "24:00", "30:00")
        let cross = timed("2026-11-03", "2026-11-04", "24:00", "06:00")
        #expect(shape(OvernightDisplay(afterMidnight: .cross).apply(keep)) == ["2026-11-03", "24:00", "2026-11-04", "06:00"])
        #expect(shape(OvernightDisplay(afterMidnight: .keep).apply(cross)) == ["2026-11-03", "24:00", "2026-11-03", "30:00"])
        #expect(shape(OvernightDisplay(afterMidnight: .next).apply(keep)) == ["2026-11-04", "00:00", "2026-11-04", "06:00"])
        // 日付をまたぐ予定の選び方は、開始が24時以降の予定には効かない
        #expect(OvernightDisplay(lateEnd: .fit).apply(cross) == cross)
    }

    @Test func allDayAndLongEventsAreUnchanged() {
        let allDay = ev("a", "2026-11-03", "2026-11-04")
        #expect(OvernightDisplay(lateEnd: .fit).apply(allDay) == allDay)
        let long = timed("2026-11-03", "2026-11-05", "22:00", "06:00")
        #expect(OvernightDisplay(lateEnd: .fit).apply(long) == long)
    }

    @Test func savedPerCalendar() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        OvernightDisplay.save(OvernightDisplay(lateEnd: .fit), for: "a", defaults: defaults)
        #expect(OvernightDisplay.load("a", defaults: defaults) == OvernightDisplay(lateEnd: .fit))
        #expect(OvernightDisplay.load("b", defaults: defaults).isDefault)
        // 投稿した人のままに戻したら、記録は消す
        OvernightDisplay.save(OvernightDisplay(), for: "a", defaults: defaults)
        #expect(OvernightDisplay.loadAll(defaults: defaults).isEmpty)
    }
}
