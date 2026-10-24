import Foundation

struct SummaryCardsData {
    let weekStart: String
    let weekEnd: String
    let weekHours: Double
    let prevWeekHours: Double
    let monthHours: Double
    let prevMonthHours: Double
    let monthPay: Double
    let prevMonthPay: Double
    let weekLabel: String
    let monthLabel: String
    let payLabel: String
}

extension Store {
    /// 期間内の合計時間と見込み給料(職場フィルタは totals と同じ)
    func periodTotals(from: String, to: String, isHoliday: (String) -> Bool = { _ in false }) -> (hours: Double, pay: Double) {
        let list = totals(from: from, to: to, isHoliday: isHoliday)
        return (list.reduce(0) { $0 + $1.hours }, list.reduce(0) { $0 + $1.pay })
    }

    func summaryCards(selectedDate: String?, today: String, anchor: String, startMonday: Bool,
                      payBasis: PayBasis = .work,
                      isHoliday: (String) -> Bool = { _ in false }) -> SummaryCardsData {
        let ws = Rules.weekStart(of: selectedDate ?? today, startMonday: startMonday)
        let we = Rules.addDays(ws, 6)
        let pws = Rules.addDays(ws, -7)
        let pwe = Rules.addDays(ws, -1)
        let mb = Rules.monthBounds(of: anchor)
        let pmb = Rules.monthBounds(of: Rules.addMonths(anchor, -1))
        let w = periodTotals(from: ws, to: we, isHoliday: isHoliday)
        let pw = periodTotals(from: pws, to: pwe, isHoliday: isHoliday)
        let m = periodTotals(from: mb.first, to: mb.last, isHoliday: isHoliday)
        let pm = periodTotals(from: pmb.first, to: pmb.last, isHoliday: isHoliday)
        let mp = monthlyPay(anchor: anchor, basis: payBasis, isHoliday: isHoliday)
        let pmp = monthlyPay(anchor: Rules.addMonths(anchor, -1), basis: payBasis, isHoliday: isHoliday)
        let labels = Rules.weekdayLabels(startMonday: false)
        let wsd = Rules.ymd(ws), wed = Rules.ymd(we), am = Rules.ymd(anchor)
        let endPart = wsd.month == wed.month ? "\(wed.day)日" : "\(wed.month)月\(wed.day)日"
        let weekLabel = "\(wsd.month)月\(wsd.day)日(\(labels[Rules.weekday(ws)]))〜\(endPart)(\(labels[Rules.weekday(we)]))"
        return SummaryCardsData(weekStart: ws, weekEnd: we, weekHours: w.hours, prevWeekHours: pw.hours,
                                monthHours: m.hours, prevMonthHours: pm.hours,
                                monthPay: mp.amount, prevMonthPay: pmp.amount,
                                weekLabel: weekLabel, monthLabel: "\(am.year)年\(am.month)月", payLabel: mp.label)
    }
}

enum DeltaFormat {
    enum Trend { case up, down, flat }

    static func hours(_ delta: Double) -> (text: String, trend: Trend) {
        let r = (delta * 10).rounded() / 10
        if abs(r) == 0 { return ("±0h", .flat) }
        var n = String(format: "%.1f", abs(r))
        if n.hasSuffix(".0") { n.removeLast(2) }
        return r > 0 ? ("+\(n)h ↑", .up) : ("-\(n)h ↓", .down)
    }

    static func yen(_ delta: Double) -> (text: String, trend: Trend) {
        let r = delta.rounded()
        if r == 0 { return ("±¥0", .flat) }
        return r > 0 ? ("+\(Money.yen(abs(r))) ↑", .up) : ("-\(Money.yen(abs(r))) ↓", .down)
    }
}
