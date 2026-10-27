import SwiftUI

/// 予定バーの文字サイズを、実際のカレンダーを見ながらスライダーで調整する(カレンダーは操作できない)
struct BarFontSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mode") private var calendarMode: CalendarMode = .week
    @AppStorage("startMonday") private var startMonday = false
    @AppStorage(BarFontSize.monthKey) private var monthDelta = 0.0
    @AppStorage(BarFontSize.weekKey) private var weekDelta = 0.0
    @State private var target: CalendarMode = .week

    private var delta: Binding<Double> { target == .month ? $monthDelta : $weekDelta }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("表示", selection: $target) {
                    Text("週").tag(CalendarMode.week)
                    Text("月").tag(CalendarMode.month)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                Divider()
                preview
                    .allowsHitTesting(false)
                    .frame(maxHeight: .infinity)
                Divider()
                VStack(spacing: 8) {
                    HStack {
                        Text("文字サイズ").font(.app(14))
                        Spacer()
                        Text(label(delta.wrappedValue))
                            .font(.app(14, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Theme.accent)
                        Button("標準に戻す") { delta.wrappedValue = 0 }
                            .font(.app(13))
                            .disabled(delta.wrappedValue == 0)
                    }
                    HStack(spacing: 10) {
                        Text("小").font(.app(11)).foregroundStyle(.secondary)
                        Slider(value: delta, in: BarFontSize.range, step: 0.1)
                        Text("大").font(.app(15)).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            .navigationTitle("予定バーの文字サイズ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } }
        }
        .onAppear { target = calendarMode }
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
                      onSelectDay: { _ in }, onSelectEvent: { _ in }, onDropEvent: { _, _ in },
                      onSelectPayday: { _ in }, onLongPressDay: { _ in })
        case .week:
            WeekView(anchor: today, startMonday: startMonday, summaryOn: false, selectedDate: nil,
                     onSelectDay: { _ in }, onSelectEvent: { _ in }, onDropEvent: { _, _ in },
                     onSelectPayday: { _ in }, onLongPressDay: { _ in })
        }
    }
}
