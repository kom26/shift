import Foundation

enum CSVExport {
    static func fileName(for anchor: String) -> String {
        let (y, m, _) = Rules.ymd(anchor)
        return String(format: "shifts_%04d%02d.csv", y, m)
    }

    static func make(events: [ShiftEvent], month anchor: String) -> String {
        let b = Rules.monthBounds(of: anchor)
        func row(_ cells: [String]) -> String {
            cells.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",")
        }
        func hours(_ e: ShiftEvent) -> String { e.workHours.map { Rules.formatHours($0) } ?? "" }

        let placed = events.enumerated()
            .filter { item in
                guard item.element.placed, let sd = item.element.startDate else { return false }
                return sd >= b.first && sd <= b.last
            }
            .sorted { a, c in
                let da = a.element.startDate ?? "", dc = c.element.startDate ?? ""
                return da != dc ? da < dc : a.offset < c.offset
            }
            .map(\.element)
        var lines = [row(["状態", "日付", "開始", "終了", "実労働時間", "メモ"])]
        for e in placed {
            lines.append(row(["配置済", (e.startDate ?? "").replacingOccurrences(of: "-", with: "/"),
                              e.startTime ?? "", e.endTime ?? "", hours(e), e.memo]))
        }
        for e in events where !e.placed {
            lines.append(row(["未配置", "", e.startTime ?? "", e.endTime ?? "", hours(e), e.memo]))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n")
    }
}
