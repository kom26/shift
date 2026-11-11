import SwiftUI

/// 予定バーのフォント・文字サイズ(タイトルと時間を別々に)・太さを、実際のカレンダーを見ながら調整する(カレンダーは操作できない)。
/// カレンダーは、アプリと同じ高さで出して、下から、設定のシート(スクロールなし)を重ねる。
/// 予定が入っていなくても見た目が分かるよう、はじめは、架空の予定(例)を出す。「自分の予定」にも切り替えられる
struct BarFontSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store
    @AppStorage("mode") private var calendarMode: CalendarMode = .week
    @AppStorage("startMonday") private var startMonday = false
    @AppStorage("summaryOn") private var summaryOn = false
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
    /// true は、架空の予定(例)。false は、自分の予定
    @State private var useSample = true
    @State private var sampleStore: Store?

    private var timeDelta: Binding<Double> { target == .month ? $monthDelta : $weekDelta }
    private var titleDelta: Binding<Double> { target == .month ? $monthTitleDelta : $weekTitleDelta }
    private var choice: BarFontChoice { BarFontChoice(rawValue: barFont) ?? .zen }

    /// カレンダーの高さ。アプリの月・週の表示と同じ決まり(曜日の行 + 5 週 + 月計)で、縮めたり伸ばしたりしない
    private var calendarHeight: CGFloat {
        LayoutMath.monthCalendarHeight(available: UIScreen.main.bounds.height - 140, weeks: 5)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        TwoWayPicker("表示", selection: $target, first: ("週", CalendarMode.week), second: ("月", CalendarMode.month))
                        TwoWayPicker("プレビュー", selection: $useSample, first: ("予定(例)", true), second: ("自分の予定", false))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    Divider()
                    preview
                        .allowsHitTesting(false)
                        .frame(height: calendarHeight)
                        .clipped()
                    Spacer(minLength: 0)
                }
                controls
            }
            .navigationTitle("予定バーの文字と太さ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } }
        }
        .onAppear {
            target = calendarMode
            if sampleStore == nil { sampleStore = BarSample.store(startMonday: startMonday) }
        }
        .onChange(of: startMonday) { _, new in sampleStore = BarSample.store(startMonday: new) }
        // 文字を大きくして、いまのバーに入らなくなったら、バーも太くする
        .onChange(of: monthDelta) { _, _ in raiseThicknessIfNeeded() }
        .onChange(of: monthTitleDelta) { _, _ in raiseThicknessIfNeeded() }
    }

    private func raiseThicknessIfNeeded() {
        if thickness > 0, thickness < Double(minThickness) { thickness = Double(minThickness) }
    }

    /// 設定の部分。スクロールせず、項目を全部出す。カレンダーの下のほうは、この下に隠れる
    private var controls: some View {
        VStack(spacing: 12) {
            fontPicker
            slider("タイトルの文字サイズ", value: titleDelta)
            slider("時間の文字サイズ", value: timeDelta)
            if target == .month { monthControls }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.18), radius: 10, y: -3)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    /// フォント。プルダウンで選ぶ(予定バーの文字だけに効く)。名前だけを 1 行で出す
    private var fontPicker: some View {
        HStack {
            Text("フォント").font(.app(14)).lineLimit(1)
            Spacer()
            Menu {
                Picker("フォント", selection: $barFont) {
                    ForEach(BarFontChoice.allCases) { Text($0.label).tag($0.rawValue) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(choice.label).font(.app(14)).lineLimit(1).fixedSize()
                    Image(systemName: "chevron.up.chevron.down").font(.app(11))
                }
            }
        }
    }

    private func slider(_ name: String, value: Binding<Double>) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(name).font(.app(14)).lineLimit(1)
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
            Text("入りきらない予定").font(.app(14)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 2)
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

    /// プレビューに使うストア(例なら、架空の予定を入れた仮のもの)
    private var shownStore: Store { useSample ? (sampleStore ?? store) : store }

    @ViewBuilder
    private var preview: some View {
        let today = Rules.today()
        switch target {
        case .month:
            MonthView(anchor: today, startMonday: startMonday, summaryOn: summaryOn, selectedDate: nil,
                      onSelectDay: { _ in }, onSelectEvent: { _ in }, onTapEvent: { _, _ in }, onDropEvent: { _, _ in },
                      onSelectPayday: { _ in }, onLongPressDay: { _ in })
                .environment(shownStore)
        case .week:
            WeekView(anchor: today, startMonday: startMonday, summaryOn: summaryOn, selectedDate: nil,
                     onSelectDay: { _ in }, onSelectEvent: { _ in }, onTapEvent: { _, _ in }, onDropEvent: { _, _ in },
                     onSelectPayday: { _ in }, onLongPressDay: { _ in })
                .environment(shownStore)
        }
    }
}
