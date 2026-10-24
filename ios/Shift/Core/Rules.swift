import Foundation

enum DayType { case normal, saturday, sunday, holiday }

/// 日付は "yyyy-MM-dd" 文字列で扱い、計算時だけ正午のDateに変換する(夏時間や時差の影響を避けるため)
enum Rules {
    private static let cal = Calendar(identifier: .gregorian)

    /// 開始時刻の上限(27:00)と終了時刻の上限(36:00)。分で表す
    static let maxStartMinutes = 27 * 60
    static let maxEndMinutes = 36 * 60

    /// 手入力の時刻("0930" / "09:30")を "HH:mm" に正規化する。不正・上限超えなら nil
    static func parseTimeDigits(_ text: String, maxMinutes: Int) -> String? {
        let digits = text.filter { $0.isASCII && $0.isNumber }
        guard digits.count == 4, let v = Int(digits) else { return nil }
        let h = v / 100, m = v % 100
        guard m <= 59, h * 60 + m <= maxMinutes else { return nil }
        return String(format: "%02d:%02d", h, m)
    }

    /// ホイールの時の候補(0...maxHour)
    static func hourOptions(maxHour: Int) -> [Int] { Array(0...maxHour) }

    /// ホイールの分の候補(0,5,...,55)
    static let minuteOptions: [Int] = Array(stride(from: 0, to: 60, by: 5))

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

    /// 隣接月の日付も含む月グリッド(各週7日)。行数は monthWeeks と同じ
    static func monthGrid(year: Int, month: Int, startMonday: Bool) -> [[String]] {
        let first = String(format: "%04d-%02d-01", year, month)
        let start = weekStart(of: first, startMonday: startMonday)
        let rows = monthWeeks(year: year, month: month, startMonday: startMonday).count
        return (0..<rows).map { r in (0..<7).map { c in addDays(start, r * 7 + c) } }
    }

    static func isSameMonth(_ ds: String, as anchor: String) -> Bool {
        let a = ymd(ds), b = ymd(anchor)
        return a.year == b.year && a.month == b.month
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

    static func daysBetween(_ a: String, _ b: String) -> Int {
        guard let da = parse(a), let db = parse(b) else { return 0 }
        return cal.dateComponents([.day], from: da, to: db).day ?? 0
    }

    /// 開始時刻の昇順(終日・時刻なしは末尾)、同時刻は勤務時間の短い順、同値は元の順(Web版 sortUnplaced 相当)
    static func sortUnplaced(_ evs: [ShiftEvent]) -> [ShiftEvent] {
        func key(_ e: ShiftEvent) -> String { e.allDay ? "99:99" : (e.startTime ?? "99:99") }
        func hours(_ e: ShiftEvent) -> Double { e.effectiveHours ?? 999 }
        return evs.enumerated().sorted { a, b in
            let ka = key(a.element), kb = key(b.element)
            if ka != kb { return ka < kb }
            let ha = hours(a.element), hb = hours(b.element)
            if ha != hb { return ha < hb }
            return a.offset < b.offset
        }.map(\.element)
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
        let sm = minutes(st) ?? 0, em = minutes(et) ?? 0
        // 24:00以降の時刻を含む予定は月ビューでは開始日のみ(単日バー)
        if sm >= 1440 || em >= 1440 { return sd }
        if em <= sm { return addDays(sd, 1) }
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

    /// 週ビューの1日分の縦位置(0...1)。開始日の0:00からの分で [s, e) を求め、表示日の範囲と交差させる
    static func timedSegment(_ ev: ShiftEvent, on ds: String) -> (top: Double, height: Double)? {
        guard !ev.allDay, let start = ev.startDate else { return nil }
        let k = daysBetween(start, ds)
        guard k >= 0 else { return nil }
        let endDate = ev.endDate ?? start
        let s = minutes(ev.startTime) ?? 0
        var e = daysBetween(start, endDate) * 1440 + (minutes(ev.endTime) ?? 1440)
        if e <= s && endDate == start { e = 1440 }
        let lo = 1440 * k, hi = 1440 * (k + 1)
        let from = max(s, lo), to = min(e, hi)
        guard to > from else { return nil }
        let top = Double(from - lo) / 1440
        let height = min(max(30, to - from), 1440 - (from - lo))
        return (top, Double(height) / 1440)
    }
}
