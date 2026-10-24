import Foundation

enum PayBasis: String {
    case work, payday
}

struct MonthlyPay {
    let amount: Double
    let label: String
}

extension Store {
    /// anchor の月の給与。.work は勤務ベース、.payday はその月に支払われる給与の合計
    func monthlyPay(anchor: String, basis: PayBasis, isHoliday: (String) -> Bool = { _ in false }) -> MonthlyPay {
        let mb = Rules.monthBounds(of: anchor)
        switch basis {
        case .work:
            let t = periodTotals(from: mb.first, to: mb.last, isHoliday: isHoliday)
            let a = Rules.ymd(anchor)
            return MonthlyPay(amount: t.pay, label: "\(a.year)年\(a.month)月勤務分")
        case .payday:
            var rows: [PaymentRow] = []
            var d = mb.first
            while d <= mb.last {
                rows += payments(onPayday: d, isHoliday: isHoliday).filter {
                    checkedWorkplaces.isEmpty || checkedWorkplaces.contains($0.workplace.id)
                }
                d = Rules.addDays(d, 1)
            }
            guard let start = rows.map(\.start).min(), let end = rows.map(\.end).max() else {
                return MonthlyPay(amount: 0, label: "給料日なし")
            }
            let amount = rows.reduce(0) { $0 + $1.amount }
            let s = Rules.ymd(start), e = Rules.ymd(end)
            let label = (s.year == e.year && s.month == e.month)
                ? "\(s.year)年\(s.month)月勤務分"
                : "\(s.month)/\(s.day)〜\(e.month)/\(e.day)勤務分"
            return MonthlyPay(amount: amount, label: label)
        }
    }
}
