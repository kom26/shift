import Foundation
import Testing
@testable import Shift

struct AlarmMathTests {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    private func shift(_ date: String, _ start: String) -> ShiftEvent {
        var e = ShiftEvent.new(on: date)
        e.allDay = false
        e.startTime = start
        e.endTime = "23:00"
        return e
    }

    @Test func labels() {
        #expect(AlarmPreset(kind: .clock, minutes: 390).label == "6:30")
        #expect(AlarmPreset(kind: .beforeShift, minutes: 180).label == "シフト3時間前")
        #expect(AlarmPreset(kind: .beforeShift, minutes: 90).label == "シフト1時間30分前")
        #expect(AlarmPreset(kind: .beforeShift, minutes: 45).label == "シフト45分前")
    }

    @Test func clockFireDate() throws {
        let p = AlarmPreset(kind: .clock, minutes: 390)
        let d = try #require(AlarmMath.fireDate(preset: p, on: "2026-10-27", events: [], calendar: cal))
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        #expect(c.day == 27 && c.hour == 6 && c.minute == 30)
    }

    @Test func beforeShiftUsesEarliestStart() throws {
        let p = AlarmPreset(kind: .beforeShift, minutes: 180)
        let events = [shift("2026-10-27", "17:00"), shift("2026-10-27", "13:30"), shift("2026-10-28", "09:00")]
        let d = try #require(AlarmMath.fireDate(preset: p, on: "2026-10-27", events: events, calendar: cal))
        let c = cal.dateComponents([.hour, .minute], from: d)
        #expect(c.hour == 10 && c.minute == 30)
    }

    @Test func beforeShiftWithoutShiftIsNil() {
        let p = AlarmPreset(kind: .beforeShift, minutes: 180)
        #expect(AlarmMath.fireDate(preset: p, on: "2026-10-27", events: [], calendar: cal) == nil)
    }

    @Test func beforeShiftCanCrossIntoPreviousDay() throws {
        let p = AlarmPreset(kind: .beforeShift, minutes: 180)
        let d = try #require(AlarmMath.fireDate(preset: p, on: "2026-10-27", events: [shift("2026-10-27", "01:00")], calendar: cal))
        let c = cal.dateComponents([.day, .hour], from: d)
        #expect(c.day == 26 && c.hour == 22)
    }
}
