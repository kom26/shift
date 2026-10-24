import Foundation

/// 職場ごとの締め日・給料日の計算
enum PayCycle {
    private static func daysInMonth(_ year: Int, _ month: Int) -> Int {
        let first = String(format: "%04d-%02d-01", year, month)
        return Rules.ymd(Rules.monthBounds(of: first).last).day
    }

    private static func resolvedDay(_ day: Int, year: Int, month: Int) -> Int {
        let n = daysInMonth(year, month)
        return day == 0 ? n : min(day, n)
    }

    /// month を delta か月ずらした (year, month)
    private static func shifted(year: Int, month: Int, by delta: Int) -> (year: Int, month: Int) {
        let idx = year * 12 + (month - 1) + delta
        return (Int((Double(idx) / 12).rounded(.down)), ((idx % 12) + 12) % 12 + 1)
    }

    static func closeDate(year: Int, month: Int, closingDay: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, resolvedDay(closingDay, year: year, month: month))
    }

    static func isPayday(_ ds: String, workplace: Workplace) -> Bool {
        guard let pd = workplace.paydayDay else { return false }
        let (y, m, d) = Rules.ymd(ds)
        return d == resolvedDay(pd, year: y, month: m)
    }

    static func period(forPayday ds: String, workplace: Workplace) -> (start: String, end: String)? {
        guard isPayday(ds, workplace: workplace) else { return nil }
        let (y, m, _) = Rules.ymd(ds)
        let c = shifted(year: y, month: m, by: -workplace.paydayMonthOffset)
        let p = shifted(year: c.year, month: c.month, by: -1)
        let end = closeDate(year: c.year, month: c.month, closingDay: workplace.closingDay)
        let prevClose = closeDate(year: p.year, month: p.month, closingDay: workplace.closingDay)
        return (Rules.addDays(prevClose, 1), end)
    }
}
