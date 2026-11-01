import SwiftUI

struct PaydaySheet: View {
    @Environment(Store.self) private var store
    @Environment(Holidays.self) private var holidays
    @Environment(\.dismiss) private var dismiss

    let date: String

    private func short(_ ds: String) -> String {
        let p = Rules.ymd(ds)
        return "\(p.month)/\(p.day)"
    }

    var body: some View {
        let rows = store.payments(onPayday: date, isHoliday: { holidays.name(on: $0) != nil })
        NavigationStack {
            List {
                if rows.isEmpty {
                    Text("この日に給料が入る職場はありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rows) { r in
                        NavigationLink {
                            PaydayDetail(row: r)
                        } label: {
                            HStack(spacing: 8) {
                                ColorDot(hex: r.workplace.color, size: 10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.workplace.name)
                                    Text("\(short(r.start))〜\(short(r.end))")
                                        .font(.app(12))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Text(Money.yen(r.amount)).monospacedDigit()
                            }
                        }
                    }
                    HStack {
                        Text("合計").fontWeight(.bold)
                        Spacer()
                        Text(Money.yen(rows.reduce(0) { $0 + $1.amount }))
                            .fontWeight(.bold)
                            .monospacedDigit()
                    }
                }
            }
            .navigationTitle("\(short(date)) の給料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 職場ごとの給料の内訳(予定追加の見込み給与と同じ並び。期間内の予定の合計)
private struct PaydayDetail: View {
    let row: Store.PaymentRow

    var body: some View {
        List {
            Section {
                PayBreakdownRows(p: row.breakdown, transportLabel: "交通費") {
                    if row.breakdown.adjustment != 0 {
                        LabeledContent("一律加給・調整給", value: Money.yen(row.breakdown.adjustment))
                            .font(.app(13))
                    }
                }
            } footer: {
                let s = Rules.ymd(row.start), e = Rules.ymd(row.end)
                Text("\(s.month)/\(s.day)〜\(e.month)/\(e.day)の勤務分")
            }
        }
        .navigationTitle(row.workplace.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
