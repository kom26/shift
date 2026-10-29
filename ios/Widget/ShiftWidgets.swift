import SwiftUI
import WidgetKit

@main
struct ShiftWidgets: WidgetBundle {
    init() { AppFont.register() }

    var body: some Widget {
        ShiftDayWidget()
        ShiftWeekWidget()
    }
}

/// 次の0時。日付が変わったら「今日」に戻すために、この時刻に表示を作り直す
func nextMidnight(after date: Date = Date()) -> Date {
    let cal = Calendar.current
    return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date)) ?? date.addingTimeInterval(3600)
}

/// 前へ・次へなどの小さな丸ボタン
struct WidgetStepButtonLabel: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.primary)
            .frame(width: 26, height: 22)
            .background(Capsule().fill(Color(.secondarySystemFill)))
    }
}

/// 「今日へ」「今週へ」の紫のボタン
struct WidgetBackLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.app(10.5, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Capsule().fill(Theme.accent))
    }
}
