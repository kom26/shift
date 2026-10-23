import Foundation
import Testing
@testable import Shift

struct CSVExportTests {
    @Test func fileName() {
        #expect(CSVExport.fileName(for: "2026-10-15") == "shifts_202610.csv")
    }

    @Test func makeBuildsBomHeaderPlacedThenUnplaced() {
        var late = ev("late", "2026-10-20", allDay: false, st: "10:00", et: "14:00")
        late.memo = "say \"hi\""
        var early = ev("early", "2026-10-05", allDay: false, st: "09:00", et: "18:00", wh: 8)
        early.memo = "メモ"
        let other = ev("other", "2026-11-01")
        var un = ev("un", nil, allDay: false, placed: false, st: "15:00", et: "23:00", wh: 7.25)
        un.memo = "m"
        let allDayUn = ev("au", nil, placed: false)
        let csv = CSVExport.make(events: [late, other, early, un, allDayUn], month: "2026-10-15")
        let lines = csv.components(separatedBy: "\r\n")
        #expect(csv.hasPrefix("\u{FEFF}"))
        #expect(lines[0] == "\u{FEFF}\"状態\",\"日付\",\"開始\",\"終了\",\"実労働時間\",\"メモ\"")
        #expect(lines[1] == "\"配置済\",\"2026/10/05\",\"09:00\",\"18:00\",\"8h\",\"メモ\"")
        #expect(lines[2] == "\"配置済\",\"2026/10/20\",\"10:00\",\"14:00\",\"\",\"say \"\"hi\"\"\"")
        #expect(lines[3] == "\"未配置\",\"\",\"15:00\",\"23:00\",\"7h15m\",\"m\"")
        #expect(lines[4] == "\"未配置\",\"\",\"\",\"\",\"\",\"\"")
        #expect(lines.count == 5)
    }
}
