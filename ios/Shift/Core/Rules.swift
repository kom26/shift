import Foundation

enum DayType { case normal, saturday, sunday, holiday }

/// 日付は "yyyy-MM-dd" 文字列で扱い、計算時だけ正午のDateに変換する(夏時間や時差の影響を避けるため)
enum Rules {
    private static let cal = Calendar(identifier: .gregorian)

    static let timeOptions: [String] = (0...48).map { String(format: "%02d:%@", $0 / 2, $0 % 2 == 0 ? "00" : "30") }

    // MARK: 日付

    static func ymd(_ s: String) -> (year: Int, month: Int, day: Int) {
        let p = s.split(separator: "-").compactMap { Int($0) }
        return p.count == 3 ? (p[0], p[1], p[2]) : (1970, 1, 1)
    }

    static func parse(_ s: String) -> Date? {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))
    }

    static func format(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func today() -> String { format(Date()) }

    /// 0 = 日曜 … 6 = 土曜(JSの getDay() と同じ)
    static func weekday(_ s: String) -> Int {
        guard let d = parse(s) else { return 0 }
        return cal.component(.weekday, from: d) - 1
    }

    static func addDays(_ s: String, _ n: Int) -> String {
        guard let d = parse(s), let r = cal.date(byAdding: .day, value: n, to: d) else { return s }
        return format(r)
    }

    static func addMonths(_ s: String, _ n: Int) -> String {
        guard let d = parse(s), let r = cal.date(byAdding: .month, value: n, to: d) else { return s }
        return format(r)
    }

    static func weekStart(of s: String, startMonday: Bool) -> String {
        let day = weekday(s)
        let offset = startMonday ? (day == 0 ? -6 : 1 - day) : -day
        return addDays(s, offset)
    }

    static func monthWeeks(year: Int, month: Int, startMonday: Bool) -> [[String?]] {
        let first = String(format: "%04d-%02d-01", year, month)
        let w = weekday(first)
        let offset = startMonday ? (w + 6) % 7 : w
        let days = cal.range(of: .day, in: .month, for: parse(first)!)!.count
        var cells: [String?] = Array(repeating: nil, count: offset)
        for d in 1...days { cells.append(String(format: "%04d-%02d-%02d", year, month, d)) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    static func monthBounds(of s: String) -> (first: String, last: String) {
        let (y, m, _) = ymd(s)
        let first = String(format: "%04d-%02d-01", y, m)
        let days = cal.range(of: .day, in: .month, for: parse(first)!)!.count
        return (first, String(format: "%04d-%02d-%02d", y, m, days))
    }

    static func weekdayLabels(startMonday: Bool) -> [String] {
        let sun = ["日", "月", "火", "水", "木", "金", "土"]
        return startMonday ? Array(sun[1...]) + [sun[0]] : sun
    }

    static func dateInRange(_ ds: String, _ start: String, _ end: String?) -> Bool {
        ds >= start && ds <= (end ?? start)
    }

    static func dayType(_ ds: String, isHoliday: Bool) -> DayType {
        if isHoliday { return .holiday }
        switch weekday(ds) {
        case 0: return .sunday
        case 6: return .saturday
        default: return .normal
        }
    }

    // MARK: 時間

    static func resolveEndDate(start: String?, end: String?, allDay: Bool, startTime: String?, endTime: String?) -> String? {
        guard let sd = start.nonEmpty else { return end }
        let ed = end.nonEmpty
        guard !allDay, let st = startTime.nonEmpty, let et = endTime.nonEmpty else { return ed ?? sd }
        if et == "24:00" { return ed ?? sd }
        if et <= st { return addDays(sd, 1) }
        if let ed, ed >= sd { return ed }
        return sd
    }

    static func minutes(_ t: String?) -> Int? {
        guard let t = t.nonEmpty else { return nil }
        let p = t.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return nil }
        return p[0] * 60 + p[1]
    }

    static func totalMinutes(start: String?, end: String?) -> Int? {
        guard let s = minutes(start), let e = minutes(end) else { return nil }
        var m = e - s
        if m <= 0 { m += 1440 }
        return m
    }

    static func defaultBreak(_ total: Int) -> Int {
        total > 480 ? 60 : total > 360 ? 45 : 0
    }

    static func workHours(start: String?, end: String?, allDay: Bool, breakMinutes: Int? = nil) -> Double? {
        guard !allDay, let total = totalMinutes(start: start, end: end) else { return nil }
        let brk = breakMinutes ?? defaultBreak(total)
        return (Double(total - brk) / 60 * 100).rounded() / 100
    }

    /// 保存済みの workHours から、既定値と異なる休憩分を逆算する
    static func breakOverride(of ev: ShiftEvent) -> Int? {
        guard let wh = ev.workHours, !ev.allDay,
              let total = totalMinutes(start: ev.startTime, end: ev.endTime) else { return nil }
        let brk = Int((Double(total) - wh * 60).rounded())
        return brk != defaultBreak(total) ? brk : nil
    }

    static func formatHours(_ h: Double?) -> String {
        guard let h, !h.isNaN else { return "-" }
        let hh = Int(h.rounded(.down))
        let mm = Int(((h - Double(hh)) * 60).rounded())
        return mm > 0 ? "\(hh)h\(mm)m" : "\(hh)h"
    }

    static func timeLabel(_ ev: ShiftEvent) -> String {
        if ev.allDay { return "終日" }
        if let s = ev.startTime, let e = ev.endTime { return "\(s)〜\(e)" }
        if let s = ev.startTime { return "\(s)〜" }
        return ""
    }

    /// 週ビューの1日分の縦位置(0...1)。日またぎの予定は開始日・終了日・中間日で形が変わる
    static func timedSegment(_ ev: ShiftEvent, on ds: String) -> (top: Double, height: Double)? {
        guard !ev.allDay, let start = ev.startDate, dateInRange(ds, start, ev.endDate) else { return nil }
        let end = ev.endDate ?? start
        let isStart = start == ds, isEnd = end == ds
        let s = Double(minutes(ev.startTime) ?? 0)
        let e = Double(minutes(ev.endTime) ?? 1440)
        if isStart && isEnd {
            let e2 = e <= s ? 1440 : e
            return (s / 1440, max(30, e2 - s) / 1440)
        } else if isStart {
            return (s / 1440, (1440 - s) / 1440)
        } else if isEnd {
            return (0, max(30, e) / 1440)
        }
        return (0, 1)
    }
}
