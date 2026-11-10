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

struct AttachmentFieldTests {
    @Test func noteBecomesTheMemoAndIsTrimmed() {
        let raw: [[String: Any]] = [["title": "予習教材#02", "note": "  #02 倒産処理手続の開始要件 ", "dueDate": "2026-10-13"]]
        let lines = TaskLine.parse(raw)
        #expect(lines[0].note == "#02 倒産処理手続の開始要件")
        #expect(lines[0].makeTask().memo == "#02 倒産処理手続の開始要件")
    }

    @Test func oldTasksAndEventsDecodeWithoutTheNewFields() throws {
        let t = try JSONDecoder().decode(TaskItem.self, from: Data(##"{"id":"a","title":"x","color":"#fff","done":false}"##.utf8))
        #expect(t.memo == "" && t.url == nil && t.imageId == nil)
        let e = try JSONDecoder().decode(ShiftEvent.self, from: Data(##"{"id":"a","title":"x"}"##.utf8))
        #expect(e.url == nil && e.imageId == nil)
    }

    @Test func urlAndImageRoundTrip() throws {
        var t = TaskItem.new(dueDate: "2026-12-11")
        t.url = "https://example.com"; t.imageId = "img1"; t.memo = "m"
        let back = try JSONDecoder().decode(TaskItem.self, from: JSONEncoder().encode(t))
        #expect(back == t)
    }

    @Test func linkDestinationAddsASchemeAndRejectsJunk() {
        #expect(AttachmentLink.destination("example.com/a")?.absoluteString == "https://example.com/a")
        #expect(AttachmentLink.destination("http://example.com")?.absoluteString == "http://example.com")
        #expect(AttachmentLink.destination("あいう") == nil)
        #expect(AttachmentLink.destination("  ") == nil)
    }
}
