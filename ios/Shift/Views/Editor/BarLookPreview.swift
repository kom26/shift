import SwiftUI
import UIKit

/// 予定編集画面のプレビュー。月カレンダーでこの予定のバーがどう見えるかを、予定の日付で見せる
/// 1日: 1マス / 2日: 2マス / 3日: 3マス(真ん中の日も見せる) / 4日以上: 最初と最後の日だけ見せて、間は「〜」で省略する
struct BarLookPreview: View {
    let event: ShiftEvent
    @AppStorage(BarFontSize.monthKey) private var monthDelta = 0.0

    private let barH: CGFloat = 18

    private enum Column {
        case day(String?)
        case omitted
    }

    var body: some View {
        // 月カレンダーの1マスと同じ幅(画面を7等分)
        let colW = floor(UIScreen.main.bounds.width / 7)
        let omittedW = (colW * 0.7).rounded()
        let columns = self.columns
        let total = columns.reduce(CGFloat(0)) { $0 + width(of: $1, colW: colW, omittedW: omittedW) }
        let fontSize = max(5, FixedWidthTime.fitSize(width: colW - 2 - BarFontSize.sidePadding) + CGFloat(monthDelta))
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                ForEach(columns.indices, id: \.self) { i in
                    cell(columns[i])
                        .frame(width: width(of: columns[i], colW: colW, omittedW: omittedW), height: 15, alignment: .leading)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color(.separator).opacity(0.5)).frame(width: 0.5)
                        }
                }
            }
            EventBar(span: BarSpan(event: event, col: 0, span: 1, isStart: true, isEnd: true), height: barH, fontSize: fontSize)
                .frame(width: max(0, total - 2), height: barH)
                .padding(.leading, 1)
        }
        .padding(.bottom, 4)
        .frame(width: total, alignment: .leading)
        .background(Color(.systemBackground))
        .overlay(Rectangle().strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("カレンダー上の見た目のプレビュー")
    }

    private var columns: [Column] {
        guard let s = event.startDate else { return [.day(nil)] }
        let e = event.endDate ?? s
        let days = max(1, Rules.daysBetween(s, e) + 1)
        switch days {
        case 1: return [.day(s)]
        case 2: return [.day(s), .day(e)]
        case 3: return [.day(s), .day(Rules.addDays(s, 1)), .day(e)]
        default: return [.day(s), .omitted, .day(e)]
        }
    }

    private func width(of c: Column, colW: CGFloat, omittedW: CGFloat) -> CGFloat {
        if case .omitted = c { return omittedW }
        return colW
    }

    @ViewBuilder
    private func cell(_ c: Column) -> some View {
        switch c {
        case .day(let ds):
            Text(ds.map { "\(Rules.ymd($0).day)" } ?? "")
                .font(.app(10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        case .omitted:
            Text("〜")
                .font(.app(10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }
}
