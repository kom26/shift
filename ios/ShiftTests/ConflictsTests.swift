import Foundation
import Testing
@testable import Shift

struct ConflictsTests {
    private func t(_ id: String, _ sd: String, _ st: String, _ et: String, end: String? = nil) -> ShiftEvent {
        ev(id, sd, end ?? sd, allDay: false, st: st, et: et)
    }

    @Test func overlapOnSameDay() {
        let d = Conflicts.days(events: [t("a", "2026-10-01", "09:00", "18:00"), t("b", "2026-10-01", "17:00", "20:00")])
        #expect(d == ["2026-10-01"])
    }

    @Test func touchingEndsDoNotConflict() {
        let d = Conflicts.days(events: [t("a", "2026-10-01", "09:00", "12:00"), t("b", "2026-10-01", "12:00", "15:00")])
        #expect(d.isEmpty)
    }

    @Test func extendedEndSameDateReachesNextDay() {
        let d = Conflicts.days(events: [t("a", "2026-10-01", "22:00", "25:00"), t("b", "2026-10-02", "00:30", "02:00")])
        #expect(d == ["2026-10-02"])
    }

    @Test func overnightEventOverlapsNextMorning() {
        let d = Conflicts.days(events: [t("a", "2026-10-01", "22:00", "06:00", end: "2026-10-02"),
                                        t("b", "2026-10-02", "05:00", "09:00")])
        #expect(d == ["2026-10-02"])
    }

    @Test func overlapSpanningMidnightMarksBothDays() {
        let d = Conflicts.days(events: [t("a", "2026-10-01", "22:00", "06:00", end: "2026-10-02"),
                                        t("b", "2026-10-01", "23:00", "02:00", end: "2026-10-02")])
        #expect(d == ["2026-10-01", "2026-10-02"])
    }

    @Test func allDayNeverConflicts() {
        let d = Conflicts.days(events: [ev("a", "2026-10-01"), t("b", "2026-10-01", "09:00", "18:00")])
        #expect(d.isEmpty)
    }

    @Test func unplacedNeverConflicts() {
        let d = Conflicts.days(events: [t("a", "2026-10-01", "09:00", "18:00"),
                                        ev("b", nil, allDay: false, placed: false, st: "09:00", et: "18:00")])
        #expect(d.isEmpty)
    }

    @Test func identicalDuplicatesConflict() {
        let d = Conflicts.days(events: [t("a", "2026-10-01", "09:00", "18:00"), t("b", "2026-10-01", "09:00", "18:00")])
        #expect(d == ["2026-10-01"])
    }

    @Test func gapShorterThanThresholdConflicts() {
        let evs = [t("a", "2026-10-01", "09:00", "12:00"), t("b", "2026-10-01", "12:20", "15:00")]
        #expect(Conflicts.days(events: evs, minGapMinutes: 30) == ["2026-10-01"])
        #expect(Conflicts.days(events: evs, minGapMinutes: 20).isEmpty)
        #expect(Conflicts.days(events: evs, minGapMinutes: 0).isEmpty)
    }

    @Test func touchingConflictsOnlyWithPositiveThreshold() {
        let evs = [t("a", "2026-10-01", "09:00", "12:00"), t("b", "2026-10-01", "12:00", "15:00")]
        #expect(Conflicts.days(events: evs, minGapMinutes: 0).isEmpty)
        #expect(Conflicts.days(events: evs, minGapMinutes: 1) == ["2026-10-01"])
    }

    @Test func gapAcrossMidnightMarksBothDays() {
        let evs = [t("a", "2026-10-01", "22:00", "23:30"), t("b", "2026-10-02", "00:10", "03:00")]
        #expect(Conflicts.days(events: evs, minGapMinutes: 60) == ["2026-10-01", "2026-10-02"])
        #expect(Conflicts.days(events: evs, minGapMinutes: 30).isEmpty)
    }
}
