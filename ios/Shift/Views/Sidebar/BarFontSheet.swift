import SwiftUI

/// 予定バーのフォント・文字サイズ(タイトルと時間を別々に)・太さを、実際のカレンダーを見ながら調整する(カレンダーは操作できない)
struct BarFontSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mode") private var calendarMode: CalendarMode = .week
    @AppStorage("startMonday") private var startMonday = false
    /// 時間の文字サイズ
    @AppStorage(BarFontSize.monthKey) private var monthDelta = 0.0
    @AppStorage(BarFontSize.weekKey) private var weekDelta = 0.0
    /// タイトルの文字サイズ
    @AppStorage(BarFontSize.monthTitleKey) private var monthTitleDelta = 0.0
    @AppStorage(BarFontSize.weekTitleKey) private var weekTitleDelta = 0.0
    @AppStorage(BarFontChoice.key) private var barFont = BarFontChoice.zen.rawValue
    @AppStorage(BarFontSize.thicknessKey) private var thickness = 0.0
    @AppStorage(BarFontSize.scrollKey) private var scrollOnOverflow = false
    @State private var target: CalendarMode = .week

    private var timeDelta: Binding<Double> { target == .month ? $monthDelta : $weekDelta }
    private var titleDelta: Binding<Double> { target == .month ? $monthTitleDelta : $weekTitleDelta }
    private var choice: BarFontChoice { BarFontChoice(rawValue: barFont) ?? .zen }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TwoWayPicker("表示", selection: $target, first: ("週", CalendarMode.week), second: ("月", CalendarMode.month))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                Divider()
                preview
                    .allowsHitTesting(false)
                    .frame(maxHeight: .infinity)
                Divider()
                ScrollView {
                    VStack(spacing: 14) {
                        fontPicker
                        slider("タイトルの文字サイズ", value: titleDelta)
                        slider("時間の文字サイズ", value: timeDelta)
                        if target == .month { monthControls }
                    }
                    .padding(16)
                }
                .frame(maxHeight: 330)
            }
            .navigationTitle("予定バーの文字と太さ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } }
        }
        .onAppear { target = calendarMode }
        // 文字を大きくして、いまのバーに入らなくなったら、バーも太くする
        .onChange(of: monthDelta) { _, _ in raiseThicknessIfNeeded() }
        .onChange(of: monthTitleDelta) { _, _ in raiseThicknessIfNeeded() }
    }

    private func raiseThicknessIfNeeded() {
        if thickness > 0, thickness < Double(minThickness) { thickness = Double(minThickness) }
    }

    /// フォント。プルダウンで選ぶ(予定バーの文字だけに効く)
    private var fontPicker: some View {
        HStack {
            Text("フォント").font(.app(14))
            Spacer()
            Text("研修 9:00")
                .font(.custom(choice.name(for: .bold), size: 14))
                .foregroundStyle(.secondary)
            Picker("フォント", selection: $barFont) {
                ForEach(BarFontChoice.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private func slider(_ name: String, value: Binding<Double>) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(name).font(.app(14))
                Spacer()
                Text(label(value.wrappedValue))
                    .font(.app(14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
                Button("標準に戻す") { value.wrappedValue = 0 }
                    .font(.app(13))
                    .disabled(value.wrappedValue == 0)
            }
            HStack(spacing: 10) {
                Text("小").font(.app(11)).foregroundStyle(.secondary)
                Slider(value: value, in: BarFontSize.range, step: 0.1)
                Text("大").font(.app(15)).foregroundStyle(.secondary)
            }
        }
    }

    /// 月表示の文字の大きさ(実際のバーと同じ計算)。タイトルと時間の大きいほう
    private var monthFont: CGFloat {
        max(5, FixedWidthTime.fitSize(width: floor(UIScreen.main.bounds.width / 7) - 2 - BarFontSize.sidePadding)
            + CGFloat(max(monthDelta, monthTitleDelta)))
    }

    /// 文字が入る、いちばん細いバーの太さ
    private var minThickness: CGFloat { min(BarFontSize.thicknessMax - 1, BarFontSize.minBar(font: monthFont)) }

    /// 月表示だけ: バーの太さと、入りきらない予定の出し方
    private var monthControls: some View {
        VStack(spacing: 8) {
            HStack {
                Text("バーの太さ").font(.app(14))
                Spacer()
                Text(thickness == 0 ? "標準" : "\(Int(thickness))pt")
                    .font(.app(14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
                Button("標準に戻す") { thickness = 0 }
                    .font(.app(13))
                    .disabled(thickness == 0)
            }
            HStack(spacing: 10) {
                Text("細").font(.app(11)).foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { thickness == 0 ? Double(max(14, minThickness)) : max(thickness, Double(minThickness)) },
                    set: { thickness = $0 }),
                       in: Double(minThickness)...Double(BarFontSize.thicknessMax), step: 1)
                Text("太").font(.app(15)).foregroundStyle(.secondary)
            }
            Text("文字が入る、いちばん細い太さは \(Int(minThickness))pt です。")
                .font(.app(12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("入りきらない予定").font(.app(14)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
            TwoWayPicker("入りきらない予定", selection: $scrollOnOverflow, first: ("+件数で表示", false), second: ("縦にスクロール", true))
            Text(scrollOnOverflow ? "予定が多い週は、月の表示が縦にスクロールします。" : "入りきらない予定は「+件数」で表示します。")
                .font(.app(12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func label(_ v: Double) -> String {
        v == 0 ? "標準" : String(format: "%+.1f", v)
    }

    @ViewBuilder
    private var preview: some View {
        let today = Rules.today()
        switch target {
        case .month:
            MonthView(anchor: today, startMonday: startMonday, summaryOn: false, selectedDate: nil,
                      onSelectDay: { _ in }, onSelectEvent: { _ in }, onTapEvent: { _, _ in }, onDropEvent: { _, _ in },
                      onSelectPayday: { _ in }, onLongPressDay: { _ in })
        case .week:
            WeekView(anchor: today, startMonday: startMonday, summaryOn: false, selectedDate: nil,
                     onSelectDay: { _ in }, onSelectEvent: { _ in }, onTapEvent: { _, _ in }, onDropEvent: { _, _ in },
                     onSelectPayday: { _ in }, onLongPressDay: { _ in })
        }
    }
}
