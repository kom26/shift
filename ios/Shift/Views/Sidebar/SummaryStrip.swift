import SwiftUI

struct SummaryStrip: View {
    let label: String?
    let totals: [ColorTotal]
    let emptyText: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if let label {
                    Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
                if totals.isEmpty {
                    Text(emptyText).font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    ForEach(totals) { t in
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: t.color)).frame(width: 8, height: 8)
                            Text(t.title).font(.system(size: 11)).lineLimit(1)
                            Text(Rules.formatHours(t.hours)).font(.system(size: 11, weight: .semibold))
                        }
                    }
                    if totals.count > 1 {
                        Text("合計 " + Rules.formatHours(totals.reduce(0) { $0 + $1.hours }))
                            .font(.system(size: 11, weight: .bold))
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 22)
    }
}
