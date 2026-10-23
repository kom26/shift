import Testing
@testable import Shift

struct SpanLayoutTests {
    let week: [String?] = (0..<7).map { Rules.addDays("2026-10-18", $0) }

    @Test func singleDayEvent() {
        let rows = SpanLayout.rows(events: [ev("a", "2026-10-21")], weekCells: week)
        #expect(rows.count == 1)
        let s = rows[0][0]
        #expect(s.col == 3)
        #expect(s.span == 1)
        #expect(s.isStart && s.isEnd)
    }

    @Test func multiDayEvent() {
        let s = SpanLayout.rows(events: [ev("a", "2026-10-19", "2026-10-21")], weekCells: week)[0][0]
        #expect(s.col == 1)
        #expect(s.span == 3)
    }

    @Test func eventStartingBeforeWeekIsClippedAtStart() {
        let s = SpanLayout.rows(events: [ev("a", "2026-10-15", "2026-10-20")], weekCells: week)[0][0]
        #expect(s.col == 0)
        #expect(s.span == 3)
        #expect(!s.isStart)
        #expect(s.isEnd)
    }

    @Test func eventEndingAfterWeekIsClippedAtEnd() {
        let s = SpanLayout.rows(events: [ev("a", "2026-10-23", "2026-10-27")], weekCells: week)[0][0]
        #expect(s.col == 5)
        #expect(s.span == 2)
        #expect(s.isStart)
        #expect(!s.isEnd)
    }

    @Test func overlappingEventsUseSeparateRows() {
        let rows = SpanLayout.rows(events: [ev("a", "2026-10-19", "2026-10-21"), ev("b", "2026-10-20")], weekCells: week)
        #expect(rows.count == 2)
    }

    @Test func nonOverlappingEventsShareARowSortedByColumn() {
        let rows = SpanLayout.rows(events: [ev("b", "2026-10-20"), ev("a", "2026-10-19")], weekCells: week)
        #expect(rows.count == 1)
        #expect(rows[0].map(\.id) == ["a", "b"])
    }

    @Test func sameColumnKeepsInputOrder() {
        let rows = SpanLayout.rows(events: [ev("first", "2026-10-20"), ev("second", "2026-10-20")], weekCells: week)
        #expect(rows.map { $0[0].id } == ["first", "second"])
    }

    @Test func unplacedAndOutOfWeekEventsAreExcluded() {
        let events = [ev("u", nil, placed: false), ev("x", "2026-11-01"), ev("y", "2026-10-01")]
        #expect(SpanLayout.rows(events: events, weekCells: week).isEmpty)
    }

    @Test func paddedMonthWeek() {
        let cells: [String?] = [nil, nil, nil, nil, "2026-10-01", "2026-10-02", "2026-10-03"]
        let s = SpanLayout.rows(events: [ev("a", "2026-09-30", "2026-10-02")], weekCells: cells)[0][0]
        #expect(s.col == 4)
        #expect(s.span == 2)
        #expect(!s.isStart)
        #expect(s.isEnd)
    }
}
