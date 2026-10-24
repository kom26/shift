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
