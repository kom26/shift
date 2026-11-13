import Foundation
import Testing
@testable import Shift

/// ウィジェット中(1 週間)の段組み
struct WeekLanesTests {
    private let week = (0..<7).map { Rules.addDays("2026-11-08", $0) }

    private func event(_ id: String, _ start: String, _ end: String? = nil) -> ShiftEvent {
        var e = ShiftEvent.new(on: start)
        e.id = id
        e.endDate = end ?? start
        return e
    }

    private func layout(_ events: [ShiftEvent]) -> (pieces: [WeekPiece], more: [Int]) {
        WeekLanes.layout(rows: SpanLayout.rows(events: events, weekCells: week.map { Optional($0) }),
                         maxLanes: WeekContent.maxLanes)
    }

    @Test func aDayWithFourEventsShowsAllEvenIfTheCarriedEventIsHiddenOnTheDayBefore() {
        // 8 日は 5 件(うち 2 件は 9 日まで続く)。9 日は、続く 2 件と自分の 2 件で 4 件
        let events = [event("a", "2026-11-08"), event("b", "2026-11-08", "2026-11-09"), event("c", "2026-11-08"),
                      event("d", "2026-11-08"), event("e", "2026-11-08", "2026-11-09"),
                      event("f", "2026-11-09"), event("g", "2026-11-09")]
        let r = layout(events)
        #expect(r.more[0] == 2)
        #expect(r.more[1] == 0)
        // 9 日は 4 件とも出る(8 日で隠れた e は、9 日の分だけ切り出して出す)
        let onNinth = r.pieces.filter { $0.col <= 1 && $0.col + $0.count > 1 }
        #expect(Set(onNinth.map(\.span.event.id)) == ["b", "e", "f", "g"])
        #expect(r.pieces.contains { $0.span.event.id == "e" && $0.col == 1 && $0.count == 1 && !$0.startsHere })
        // 8 日の 4 段目は、「ほか○件」のために空けておく
        #expect(!r.pieces.contains { $0.lane == WeekContent.maxLanes - 1 && $0.col == 0 })
    }

    @Test func fourOrFewerEventsADayAreAllShownWithoutMore() {
        let events = [event("a", "2026-11-10"), event("b", "2026-11-10", "2026-11-12"),
                      event("c", "2026-11-11"), event("d", "2026-11-12")]
        let r = layout(events)
        #expect(r.more.allSatisfy { $0 == 0 })
        #expect(r.pieces.count == 4)
        #expect(r.pieces.allSatisfy(\.isWhole))
    }
}
