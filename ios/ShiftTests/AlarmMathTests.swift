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
        #expect(AlarmPreset(kind: .beforeShift, minutes: 180).label == "予定3時間前")
        #expect(AlarmPreset(kind: .beforeShift, minutes: 90).label == "予定1時間30分前")
        #expect(AlarmPreset(kind: .beforeShift, minutes: 45).label == "予定45分前")
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

@MainActor
struct AlarmEntriesTests {
    private func makeStore() -> Store {
        let name = UUID().uuidString
        return Store(fileURL: FileManager.default.temporaryDirectory.appending(path: "\(name).json"),
                     defaults: UserDefaults(suiteName: name)!)
    }

    private func entry(_ id: String, fire: (Int, Int, Int, Int, Int), snooze: Int? = nil) -> AlarmEntry {
        let c = DateComponents(year: fire.0, month: fire.1, day: fire.2, hour: fire.3, minute: fire.4)
        let t = Calendar.current.date(from: c)!.timeIntervalSince1970
        return AlarmEntry(id: id, kind: .clock, minutes: fire.3 * 60 + fire.4, date: "2026-11-08", fireTime: t, snoozeMinutes: snooze)
    }

    @Test func alarmsAreCountedAndOrderedByTheDayTheyRing() {
        let store = makeStore()
        store.addAlarmEntry(entry("b", fire: (2026, 11, 8, 7, 0)))
        store.addAlarmEntry(entry("a", fire: (2026, 11, 8, 6, 30)))
        store.addAlarmEntry(entry("c", fire: (2026, 11, 9, 6, 30)))
        #expect(store.alarmEntries(on: "2026-11-08").map(\.id) == ["a", "b"])
        #expect(store.alarmCount(on: "2026-11-08") == 2)
        #expect(store.alarmCount(on: "2026-11-09") == 1)
        #expect(!store.hasAlarm(on: "2026-11-10"))
    }

    @Test func updatingReplacesTheEntryAndRemovingDeletesIt() {
        let store = makeStore()
        store.addAlarmEntry(entry("a", fire: (2026, 11, 8, 6, 30)))
        store.updateAlarmEntry(entry("a", fire: (2026, 11, 8, 7, 15), snooze: 5))
        #expect(store.alarmEntries.count == 1)
        #expect(store.alarmEntries[0].minutes == 435)
        #expect(store.alarmEntries[0].snoozeMinutes == 5)
        store.updateAlarmEntry(entry("none", fire: (2026, 11, 8, 8, 0)))
        #expect(store.alarmEntries.count == 1)
        store.removeAlarmEntry(id: "a")
        #expect(store.alarmEntries.isEmpty)
    }

    @Test func oldRecordsWithoutSnoozeStillDecode() throws {
        let json = #"{"id":"x","kind":"clock","minutes":390,"date":"2026-11-08","fireTime":1000}"#
        let e = try JSONDecoder().decode(AlarmEntry.self, from: Data(json.utf8))
        #expect(e.snoozeMinutes == nil)
    }
}
