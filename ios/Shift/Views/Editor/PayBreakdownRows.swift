import SwiftUI

/// 見込み給与の内訳の行。予定追加画面と、給料日の職場別の詳細で使う。
/// 一律加給・調整給の行だけは使う側が差し込む(予定追加では入力欄、給料日では表示のみ)
struct PayBreakdownRows<Adjustment: View>: View {
    let p: PayBreakdown
    var transportLabel = "交通費(往復)"
    @ViewBuilder var adjustment: () -> Adjustment

    var body: some View {
        HStack {
            Text("見込み給与")
            Spacer()
            Text(Money.yen(p.total)).font(.app(20, weight: .bold).monospacedDigit())
        }
        row("基本給", p.netMinutes, p.base)
        if p.night > 0 { row("深夜割増", p.nightMinutes, p.night) }
        if p.overtime > 0 { row("残業割増", p.overtimeMinutes, p.overtime) }
        row("曜日加給", p.bonusMinutes, p.bonus)
        adjustment()
        if p.transport > 0 {
            LabeledContent(transportLabel, value: Money.yen(p.transport)).font(.app(13))
        }
        LabeledContent("実労働", value: Rules.formatHours(Double(p.netMinutes) / 60))
            .font(.app(13))
    }

    private func row(_ label: String, _ minutes: Int, _ amount: Double) -> some View {
        LabeledContent("\(label)(\(Rules.formatHours(Double(minutes) / 60)))", value: Money.yen(amount))
            .font(.app(13))
    }
}
