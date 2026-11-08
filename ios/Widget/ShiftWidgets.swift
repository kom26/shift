import SwiftUI
import WidgetKit

@main
struct ShiftWidgets: WidgetBundle {
    init() { AppFont.register() }

    var body: some Widget {
        ShiftWidget()
    }
}

struct ShiftEntry: TimelineEntry {
    let date: Date
    let day: DayContent
    let dayOffset: Int
    let week: WeekContent
    let weekOffset: Int
}

struct ShiftProvider: TimelineProvider {
    private func entry(now: Date = Date()) -> ShiftEntry {
        let today = Rules.today()
        let dayOffset = WidgetOffset(key: "day").current(today: today)
        let weekOffset = WidgetOffset(key: "week").current(today: today)
        // 小と中で、見るカレンダーや表示する項目を別々に決められる
        let data = WidgetBridge.read()
        let daySource = WidgetSource.load(prefs: data?.small ?? WidgetPrefs())
        let weekSource = WidgetSource.load(prefs: data?.medium ?? WidgetPrefs())
        return ShiftEntry(date: now,
                          day: daySource.dayContent(Rules.addDays(today, dayOffset)), dayOffset: dayOffset,
                          week: weekSource.weekContent(containing: Rules.addDays(today, 7 * weekOffset), today: today),
                          weekOffset: weekOffset)
    }

    func placeholder(in context: Context) -> ShiftEntry { entry() }

    func getSnapshot(in context: Context, completion: @escaping (ShiftEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ShiftEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(nextMidnight())))
    }
}

/// 小(その日の予定)と中(1週間)を1つのウィジェットにまとめている
struct ShiftWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetBridge.kind, provider: ShiftProvider()) { entry in
            ShiftWidgetView(entry: entry)
                .containerBackground(Color(.systemBackground), for: .widget)
        }
        .configurationDisplayName("シフトパレット")
        .description("小は今日の予定、中は今日を含む1週間と週の労働時間・見込み給料を見られます。")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct ShiftWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ShiftEntry

    var body: some View {
        switch family {
        case .systemMedium: MediumWeekView(content: entry.week, offset: entry.weekOffset)
        default: SmallDayView(content: entry.day, offset: entry.dayOffset)
        }
    }
}

/// 次の0時。日付が変わったら「今日」に戻すために、この時刻に表示を作り直す
func nextMidnight(after date: Date = Date()) -> Date {
    let cal = Calendar.current
    return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date)) ?? date.addingTimeInterval(3600)
}
