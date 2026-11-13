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
        // 小と中で、見るカレンダーや表示する項目を別々に決められる。
        // カレンダーを複数選んでいるときは、右上のボタンで切り替えた位置のカレンダーを見る
        let data = WidgetBridge.read()
        let smallPrefs = (data?.small ?? WidgetPrefs()).viewing(WidgetCalendarCursor(size: "small").index)
        let mediumPrefs = (data?.medium ?? WidgetPrefs()).viewing(WidgetCalendarCursor(size: "medium").index)
        var day = WidgetSource.load(prefs: smallPrefs).dayContent(Rules.addDays(today, dayOffset))
        var week = WidgetSource.load(prefs: mediumPrefs).weekContent(containing: Rules.addDays(today, 7 * weekOffset), today: today)
        day.switcher = Self.switcher(smallPrefs, data: data)
        week.switcher = Self.switcher(mediumPrefs, data: data)
        return ShiftEntry(date: now, day: day, dayOffset: dayOffset, week: week, weekOffset: weekOffset)
    }

    /// 右上の切り替えボタン。カレンダーが 1 つだけなら出さない
    static func switcher(_ prefs: WidgetPrefs, data: WidgetData?) -> WidgetCalendarSwitch? {
        guard prefs.canSwitch else { return nil }
        guard let id = prefs.calendarId else {
            // 自分のカレンダーは、自分のプロフィールのアイコン(ログインしていなければ、カレンダーの記号)
            return WidgetCalendarSwitch(icon: nil, me: data?.me.map { DayOwner(uid: $0.uid, name: $0.name, avatar: $0.avatar) })
        }
        return WidgetCalendarSwitch(icon: data?.shared?.first { $0.id == id }?.icon ?? "person.2.fill")
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
        Group {
            switch family {
            case .systemMedium: MediumWeekView(content: entry.week, offset: entry.weekOffset)
            default: SmallDayView(content: entry.day, offset: entry.dayOffset)
            }
        }
        // 端末の「文字を大きく」に合わせて文字だけが大きくなると、決まった大きさの枠からはみ出して崩れるので、
        // ウィジェットの中は、いつも標準の文字の大きさで描く(バーの丸ゴシックは Font.custom で、文字の設定に合わせて大きくなるため)
        .dynamicTypeSize(.large)
    }
}

/// 次の0時。日付が変わったら「今日」に戻すために、この時刻に表示を作り直す
func nextMidnight(after date: Date = Date()) -> Date {
    let cal = Calendar.current
    return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date)) ?? date.addingTimeInterval(3600)
}
