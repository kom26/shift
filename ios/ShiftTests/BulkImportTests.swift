import Foundation
import Testing
@testable import Shift

struct BulkImportTests {
    @Test func parseTabSeparated() {
        let rows = BulkImport.parse("早番\t7:00から15:00\n夜勤\n\n遅番\t\n")
        #expect(rows.count == 3)
        #expect(rows[0].title == "早番")
        #expect(rows[0].memo == "7:00から15:00")
        #expect(rows[1].title == "夜勤")
        #expect(rows[1].memo == "")
        #expect(rows[2].title == "遅番")
        #expect(rows[2].memo == "")
    }

    @Test func parseHandlesWindowsNewlinesAndExtraColumns() {
        let rows = BulkImport.parse("早番\t7:00から15:00\r\n夜勤\ta\tb\r\n")
        #expect(rows.count == 2)
        #expect(rows[0].title == "早番")
        #expect(rows[0].memo == "7:00から15:00")
        #expect(rows[1].title == "夜勤")
        #expect(rows[1].memo == "a")
    }

    @Test func parseDropsEmptyTitles() {
        #expect(BulkImport.parse("\t memo\n  \n").isEmpty)
    }

    @Test func makeEventsCreatesUnplacedAllDay() {
        let evs = BulkImport.makeEvents([(title: "A", memo: "m"), (title: "B", memo: "")], color: "#123456")
        #expect(evs.count == 2)
        #expect(evs[0].title == "A")
        #expect(evs[0].memo == "m")
        #expect(evs[0].color == "#123456")
        #expect(evs[0].startDate == nil)
        #expect(evs[0].endDate == nil)
        #expect(!evs[0].placed)
        #expect(evs[0].allDay)
        #expect(evs[0].startTime == nil && evs[0].endTime == nil && evs[0].workHours == nil)
        #expect(evs[0].id != evs[1].id)
    }
}
