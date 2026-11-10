import Foundation
import Testing
@testable import Shift

struct TaskLineTests {
    @Test func parsesTitlesDatesAndTimes() {
        let raw: [[String: Any]] = [
            ["title": "発表資料", "startDate": "2026-12-08", "startTime": "14:00", "dueDate": "2026-12-11", "dueTime": "17:00"],
            ["title": "本を返す", "startDate": NSNull(), "dueDate": NSNull()],
        ]
        let lines = TaskLine.parse(raw)
        #expect(lines.count == 2)
        #expect(lines[0].startTime == "14:00" && lines[0].dueTime == "17:00")
        #expect(lines[1].startDate == nil && lines[1].dueDate == nil)
    }

    @Test func dropsEmptyTitlesBadDatesAndTimesWithoutDates() {
        let raw: [[String: Any]] = [
            ["title": " ", "dueDate": "2026-12-11"],
            ["title": "A", "startDate": "2026-13-40", "startTime": "09:00", "dueDate": "2026-12-11", "dueTime": "99:00"],
        ]
        let lines = TaskLine.parse(raw)
        #expect(lines.count == 1)
        #expect(lines[0].startDate == nil && lines[0].startTime == nil)
        #expect(lines[0].dueDate == "2026-12-11" && lines[0].dueTime == nil)
    }

    @Test func dueBeforeStartDropsStartAndDuplicatesMerge() {
        let raw: [[String: Any]] = [
            ["title": "B", "startDate": "2026-12-20", "dueDate": "2026-12-10"],
            ["title": "C", "dueDate": "2026-12-11"],
            ["title": "C", "dueDate": "2026-12-11"],
        ]
        let lines = TaskLine.parse(raw)
        #expect(lines.count == 2)
        #expect(lines[0].startDate == nil)
    }

    @Test func makesATaskWithTheDefaultColor() {
        let t = TaskLine(title: "X", startDate: nil, startTime: nil, dueDate: "2026-12-11", dueTime: "17:00").makeTask()
        #expect(t.title == "X" && t.color == TaskItem.defaultColor && !t.done)
        #expect(t.dueDate == "2026-12-11" && t.dueTime == "17:00")
    }
}
