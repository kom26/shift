import SwiftUI

struct SummaryBar: View {
    let label: String
    let totals: [ColorTotal]

    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(totals) { t in
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: t.color)).frame(width: 8, height: 8)
                            Text(Rules.formatHours(t.hours)).font(.caption.weight(.medium))
                            Text("×\(t.count)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Text("計 " + Rules.formatHours(totals.reduce(0) { $0 + $1.hours }))
                .font(.caption.weight(.bold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }
}
