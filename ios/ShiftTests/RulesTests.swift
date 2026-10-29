import Foundation
import Testing
@testable import Shift

struct RulesTests {
    @Test func weekdayMatchesJS() {
        #expect(Rules.weekday("2026-10-18") == 0)
        #expect(Rules.weekday("2026-10-24") == 6)
    }

    @Test func addDaysCrossesMonthAndYear() {
        #expect(Rules.addDays("2026-10-31", 1) == "2026-11-01")
        #expect(Rules.addDays("2026-01-01", -1) == "2025-12-31")
    }

    @Test func addMonthsClampsDay() {
        #expect(Rules.addMonths("2026-01-31", 1) == "2026-02-28")
        #expect(Rules.addMonths("2026-01-15", -1) == "2025-12-15")
    }

    @Test func weekStartSundayAndMonday() {
        #expect(Rules.weekStart(of: "2026-10-21", startMonday: false) == "2026-10-18")
        #expect(Rules.weekStart(of: "2026-10-21", startMonday: true) == "2026-10-19")
        #expect(Rules.weekStart(of: "2026-10-18", startMonday: true) == "2026-10-12")
    }

    @Test func monthWeeksSundayStart() {
        let w = Rules.monthWeeks(year: 2026, month: 10, startMonday: false)
        #expect(w.count == 5)
        #expect(w[0][3] == nil)
        #expect(w[0][4] == "2026-10-01")
        #expect(w[4][6] == "2026-10-31")
    }

    @Test func monthWeeksMondayStart() {
        let w = Rules.monthWeeks(year: 2026, month: 10, startMonday: true)
        #expect(w.count == 5)
        #expect(w[0][3] == "2026-10-01")
        #expect(w[4][5] == "2026-10-31")
        #expect(w[4][6] == nil)
    }

    @Test func monthBounds() {
        let b = Rules.monthBounds(of: "2026-02-10")
        #expect(b.first == "2026-02-01")
        #expect(b.last == "2026-02-28")
    }

    @Test func resolveEndDateOvernightGoesToNextDay() {
        #expect(Rules.resolveEndDate(start: "2026-10-24", end: nil, allDay: false, startTime: "22:00", endTime: "06:00") == "2026-10-25")
    }

    @Test func resolveEndDateSameDayAndMissingEnd() {
        #expect(Rules.resolveEndDate(start: "2026-10-24", end: "2026-10-24", allDay: false, startTime: "09:00", endTime: "18:00") == "2026-10-24")
        #expect(Rules.resolveEndDate(start: "2026-10-24", end: nil, allDay: false, startTime: "09:00", endTime: "18:00") == "2026-10-24")
    }

    @Test func resolveEndDateTwentyFourIsSameDay() {
        #expect(Rules.resolveEndDate(start: "2026-10-24", end: nil, allDay: false, startTime: "09:00", endTime: "24:00") == "2026-10-24")
    }

    @Test func resolveEndDateAllDayKeepsEnd() {
        #expect(Rules.resolveEndDate(start: "2026-10-24", end: "2026-10-26", allDay: true, startTime: nil, endTime: nil) == "2026-10-26")
        #expect(Rules.resolveEndDate(start: "2026-10-24", end: nil, allDay: true, startTime: nil, endTime: nil) == "2026-10-24")
    }

    @Test func resolveEndDateKeepsMultiDayAndShiftsExtendedStart() {
        #expect(Rules.resolveEndDate(start: "2026-09-22", end: nil, allDay: false, startTime: "24:00", endTime: "06:30") == "2026-09-23")
        #expect(Rules.resolveEndDate(start: "2026-10-01", end: "2026-10-03", allDay: false, startTime: "22:00", endTime: "06:00") == "2026-10-03")
    }

    @Test func resolveEndDateEndBeforeStartFallsBackToStart() {
        #expect(Rules.resolveEndDate(start: "2026-10-24", end: "2026-10-20", allDay: false, startTime: "09:00", endTime: "18:00") == "2026-10-24")
    }

    @Test func workHoursDefaultBreaks() {
        #expect(Rules.workHours(start: "09:00", end: "18:00", allDay: false) == 8.0)
        #expect(Rules.workHours(start: "07:00", end: "15:00", allDay: false) == 7.25)
        #expect(Rules.workHours(start: "22:00", end: "06:00", allDay: false) == 7.25)
        #expect(Rules.workHours(start: "10:00", end: "14:00", allDay: false) == 4.0)
        #expect(Rules.workHours(start: "09:00", end: "24:00", allDay: false) == 14.0)
    }

    @Test func defaultBreakFollowsLaborStandardsAct() {
        #expect(Rules.defaultBreak(360) == 0)
        #expect(Rules.defaultBreak(361) == 45)
        #expect(Rules.defaultBreak(481) == 45)
        #expect(Rules.defaultBreak(525) == 45)
        #expect(Rules.defaultBreak(526) == 60)
        #expect(Rules.workHours(start: "09:00", end: "17:45", allDay: false) == 8.0)
        #expect(Rules.workHours(start: "09:00", end: "17:46", allDay: false) == 7.77)
    }

    @Test func workHoursNilForAllDayOrMissingTimes() {
        #expect(Rules.workHours(start: "09:00", end: "18:00", allDay: true) == nil)
        #expect(Rules.workHours(start: nil, end: "18:00", allDay: false) == nil)
    }

    @Test func workHoursWithBreakOverride() {
        #expect(Rules.workHours(start: "09:00", end: "18:00", allDay: false, breakMinutes: 30) == 8.5)
    }

    @Test func breakOverrideDetectsNonDefault() {
        #expect(Rules.breakOverride(of: ev("a", "2026-10-24", allDay: false, st: "09:00", et: "18:00", wh: 8.5)) == 30)
        #expect(Rules.breakOverride(of: ev("a", "2026-10-24", allDay: false, st: "09:00", et: "18:00", wh: 8.0)) == nil)
        #expect(Rules.breakOverride(of: ev("a", "2026-10-24", allDay: false, st: "09:00", et: "18:00", wh: nil)) == nil)
    }

    @Test func effectiveHoursPrefersStoredValue() {
        #expect(ev("a", "2026-10-24", allDay: false, st: "09:00", et: "18:00", wh: 6).effectiveHours == 6)
        #expect(ev("a", "2026-10-24", allDay: false, st: "09:00", et: "18:00").effectiveHours == 8)
    }

    @Test func formatHours() {
        #expect(Rules.formatHours(8) == "8h")
        #expect(Rules.formatHours(7.25) == "7h15m")
        #expect(Rules.formatHours(nil) == "-")
    }

    @Test func timeLabel() {
        #expect(Rules.timeLabel(ev("a", "2026-10-24")) == "終日")
        #expect(Rules.timeLabel(ev("a", "2026-10-24", allDay: false, st: "09:00", et: "18:00")) == "09:00〜18:00")
        #expect(Rules.timeLabel(ev("a", "2026-10-24", allDay: false, st: "09:00")) == "09:00〜")
        #expect(Rules.timeLabel(ev("a", "2026-10-24", allDay: false)) == "")
    }

    @Test func dateInRange() {
        #expect(Rules.dateInRange("2026-10-20", "2026-10-19", "2026-10-21"))
        #expect(!Rules.dateInRange("2026-10-22", "2026-10-19", "2026-10-21"))
        #expect(Rules.dateInRange("2026-10-19", "2026-10-19", nil))
    }

    @Test func dayTypePriority() {
        #expect(Rules.dayType("2026-10-24", isHoliday: false) == .saturday)
        #expect(Rules.dayType("2026-10-18", isHoliday: false) == .sunday)
        #expect(Rules.dayType("2026-10-21", isHoliday: false) == .normal)
        #expect(Rules.dayType("2026-10-24", isHoliday: true) == .holiday)
    }

    @Test func timedSegmentSameDay() throws {
        let seg = try #require(Rules.timedSegment(ev("a", "2026-10-24", allDay: false, st: "09:00", et: "18:00"), on: "2026-10-24"))
        #expect(abs(seg.top - 0.375) < 0.0001)
        #expect(abs(seg.height - 0.375) < 0.0001)
    }

    @Test func timedSegmentOvernightSplitsAcrossDays() throws {
        let e = ev("a", "2026-10-24", "2026-10-25", allDay: false, st: "22:00", et: "06:00")
        let first = try #require(Rules.timedSegment(e, on: "2026-10-24"))
        #expect(abs(first.top - 22.0 / 24) < 0.0001)
        #expect(abs(first.height - 2.0 / 24) < 0.0001)
        let second = try #require(Rules.timedSegment(e, on: "2026-10-25"))
        #expect(second.top == 0)
        #expect(abs(second.height - 6.0 / 24) < 0.0001)
        #expect(Rules.timedSegment(e, on: "2026-10-26") == nil)
    }

    @Test func resolveEndDateExtendedTimesStayOnStartDate() {
        #expect(Rules.resolveEndDate(start: "2026-10-01", end: nil, allDay: false, startTime: "22:00", endTime: "25:00") == "2026-10-01")
        #expect(Rules.resolveEndDate(start: "2026-10-01", end: nil, allDay: false, startTime: "29:00", endTime: "36:00") == "2026-10-01")
        #expect(Rules.resolveEndDate(start: "2026-10-01", end: "2026-10-02", allDay: false, startTime: "22:00", endTime: "06:00") == "2026-10-02")
    }

    @Test func timedSegmentExtendedStartNextDay() throws {
        let e = ev("a", "2026-10-01", allDay: false, st: "29:00", et: "36:00")
        #expect(Rules.timedSegment(e, on: "2026-10-01") == nil)
        let seg = try #require(Rules.timedSegment(e, on: "2026-10-02"))
        #expect(abs(seg.top - 300.0 / 1440) < 0.0001)
        #expect(abs(seg.height - 420.0 / 1440) < 0.0001)
    }

    @Test func timedSegmentExtendedEndSpillsToNextDay() throws {
        let e = ev("b", "2026-10-01", allDay: false, st: "22:00", et: "25:00")
        let first = try #require(Rules.timedSegment(e, on: "2026-10-01"))
        #expect(abs(first.top - 1320.0 / 1440) < 0.0001)
        #expect(abs(first.height - 120.0 / 1440) < 0.0001)
        let second = try #require(Rules.timedSegment(e, on: "2026-10-02"))
        #expect(second.top == 0)
        #expect(abs(second.height - 60.0 / 1440) < 0.0001)
        #expect(Rules.timedSegment(e, on: "2026-10-03") == nil)
    }

    @Test func totalMinutesExtended() {
        #expect(Rules.totalMinutes(start: "29:00", end: "36:00") == 420)
        #expect(Rules.totalMinutes(start: "22:00", end: "25:00") == 180)
    }

    @Test func timedSegmentIgnoresAllDay() {
        #expect(Rules.timedSegment(ev("a", "2026-10-24"), on: "2026-10-24") == nil)
    }

    @Test func eventDecodesWebJSONWithMissingFields() throws {
        let json = ##"{"id":"s1","title":"夜勤","color":"#6366f1","startDate":null,"endDate":null,"placed":false,"allDay":false,"startTime":"22:00","endTime":"06:00","workHours":null,"_new":null}"##
        let e = try JSONDecoder().decode(ShiftEvent.self, from: Data(json.utf8))
        #expect(e.id == "s1")
        #expect(e.memo == "")
        #expect(e.startDate == nil)
        #expect(e.placed == false)
        #expect(e.startTime == "22:00")
    }

    @Test func extendedEndTextShiftsBy24h() {
        #expect(Rules.extendedEndText("02:00") == "26:00")
        #expect(Rules.extendedEndText("05:30") == "29:30")
        #expect(Rules.extendedEndText("12:00") == "36:00")
        #expect(Rules.extendedEndText("12:05") == nil)
        #expect(Rules.extendedEndText("25:00") == nil)
        #expect(Rules.extendedEndText("abc") == nil)
        #expect(Rules.extendedEndText("") == nil)
    }

    @Test func normalizedEndDateAddsDaysWhenEndBeforeStart() {
        func n(_ sd: String, _ st: String, _ ed: String, _ et: String) -> String {
            Rules.normalizedEndDate(startDate: sd, startTime: st, endDate: ed, endTime: et)
        }
        #expect(n("2026-10-01", "22:00", "2026-10-01", "06:00") == "2026-10-02")
        #expect(n("2026-10-01", "09:00", "2026-10-01", "18:00") == "2026-10-01")
        #expect(n("2026-10-01", "09:00", "2026-10-01", "09:00") == "2026-10-01")
        #expect(n("2026-10-03", "09:00", "2026-10-01", "18:00") == "2026-10-03")
        #expect(n("2026-10-01", "22:00", "2026-10-01", "25:00") == "2026-10-01")
        #expect(n("2026-10-01", "29:00", "2026-10-01", "25:00") == "2026-10-02")
        #expect(n("2026-10-01", "22:00", "2026-10-02", "01:00") == "2026-10-02")
        #expect(n("bad", "22:00", "2026-10-01", "06:00") == "2026-10-01")
        #expect(n("2026-10-01", "xx", "2026-10-01", "06:00") == "2026-10-01")
    }

    @Test func normalizedEndDateSilentTimeEditCase() {
        #expect(Rules.normalizedEndDate(startDate: "2026-09-21", startTime: "22:00", endDate: "2026-09-21", endTime: "06:00") == "2026-09-22")
    }

    @Test func spanMinutesIncludesDates() {
        func s(_ sd: String?, _ st: String?, _ ed: String?, _ et: String?) -> Int? {
            Rules.spanMinutes(startDate: sd, startTime: st, endDate: ed, endTime: et)
        }
        #expect(s("2026-10-21", "22:00", "2026-10-22", "06:00") == 480)
        #expect(s("2026-10-01", "09:00", "2026-10-03", "11:00") == 3000)
        #expect(s("2026-10-01", "22:00", "2026-10-01", "25:00") == 180)
        #expect(s("2026-10-01", "29:00", "2026-10-01", "36:00") == 420)
        #expect(s("2026-10-01", "22:00", "2026-10-01", "06:00") == 480)
        #expect(s("2026-10-01", "09:00", nil, "18:00") == 540)
        #expect(s("2026-10-01", nil, nil, "18:00") == nil)
        #expect(s(nil, "22:00", nil, "06:00") == 480)
    }

    @Test func workHoursUsesDates() {
        #expect(Rules.workHours(startDate: "2026-10-01", startTime: "09:00", endDate: "2026-10-03", endTime: "11:00", allDay: false) == 49.0)
        #expect(Rules.workHours(startDate: "2026-10-01", startTime: "09:00", endDate: "2026-10-03", endTime: "11:00", allDay: true) == nil)
        let e = ev("m", "2026-10-01", "2026-10-03", allDay: false, st: "09:00", et: "11:00")
        #expect(e.effectiveHours == 49.0)
        var f = e
        f.workHours = 48
        #expect(Rules.breakOverride(of: f) == 120)
    }

    @Test func isEndBeforeStartComparesAbsoluteMinutes() {
        func b(_ sd: String, _ st: String, _ ed: String, _ et: String) -> Bool {
            Rules.isEndBeforeStart(startDate: sd, startTime: st, endDate: ed, endTime: et)
        }
        #expect(b("2026-10-01", "22:00", "2026-10-01", "06:00") == true)
        #expect(b("2026-10-01", "22:00", "2026-10-02", "06:00") == false)
        #expect(b("2026-10-01", "09:00", "2026-10-01", "09:00") == false)
        #expect(b("2026-10-01", "09:00", "2026-10-01", "18:00") == false)
        #expect(b("2026-10-01", "22:00", "2026-10-01", "25:00") == false)
        #expect(b("2026-10-01", "29:00", "2026-10-01", "25:00") == true)
        #expect(b("2026-10-03", "09:00", "2026-10-01", "18:00") == true)
        #expect(b("2026-10-01", "09:00", "2026-10-01", "abc") == false)
    }
}
