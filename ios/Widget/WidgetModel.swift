import Foundation

/// ウィジェットが表示に使う、ストア1つぶんの読み出し
struct WidgetSource {
    let store: Store
    let holidays: Holidays
    let startMonday: Bool
    let alarms: [AlarmEntry]

    /// アプリが書き出したデータから組み立てる。まだ書き出されていなければ空のカレンダー
    static func load() -> WidgetSource {
        let name = "widget-" + UUID().uuidString
        let store = Store(fileURL: FileManager.default.temporaryDirectory.appending(path: name + ".json"),
                          defaults: UserDefaults(suiteName: name) ?? .standard)
        let data = WidgetBridge.read()
        if let data { store.applySnapshot(data.snapshot) }
        return WidgetSource(store: store, holidays: Holidays(defaults: UserDefaults(suiteName: name) ?? .standard),
                            startMonday: data?.startMonday ?? false, alarms: data?.snapshot.alarms ?? [])
    }

    func isHoliday(_ ds: String) -> Bool { holidays.name(on: ds) != nil }
}

struct DayAlarmBadge: Equatable {
    let first: String
    let more: Int
}

struct DayEventLine: Identifiable, Equatable {
    let id: String
    let title: String
    let color: String
    let label: String
    let hours: String
    let isAllDay: Bool
    let showsTime: Bool
}

struct DayContent: Equatable {
    let date: String
    let weekday: String
    let weekdayType: DayType
    let pay: String?
    let alarm: DayAlarmBadge?
    let events: [DayEventLine]
}

struct WeekBar: Identifiable, Equatable {
    let id: String
    let col: Int
    let span: Int
    let lane: Int
    let text: String
    let color: String
    let showsTime: Bool
}

struct WeekContent: Equatable {
    let title: String
    let days: [String]
    let dayNumbers: [Int]
    let dayTypes: [DayType]
    let todayCol: Int?
    let bars: [WeekBar]
    let hours: String
    let pay: String
}

extension WidgetSource {
    private static let weekdays = ["日", "月", "火", "水", "木", "金", "土"]

    func dayContent(_ ds: String) -> DayContent {
        let summary = store.daySummary(date: ds, isHoliday: isHoliday)
        let lines = summary.events.map { row -> DayEventLine in
            let ev = row.event
            let hours = ev.effectiveHours.flatMap { $0 > 0 && !ev.allDay ? Rules.formatHours($0) : nil } ?? ""
            let label = row.isAllDay ? "終日" : (ev.startTime == nil ? "" : Rules.timeLabel(ev))
            return DayEventLine(id: ev.id, title: ev.title, color: ev.color, label: label, hours: hours,
                                isAllDay: row.isAllDay, showsTime: !row.isAllDay && ev.startTime != nil)
        }
        let paid = summary.paydays.reduce(0) { $0 + $1.amount }
        let pay = summary.paydays.isEmpty ? nil : "給料日 " + Money.yen(paid)
        let fires = alarms.filter { $0.date == ds }.map(\.fireTime).sorted()
        let alarm = fires.first.map { first -> DayAlarmBadge in
            let f = DateFormatter()
            f.dateFormat = "H:mm"
            return DayAlarmBadge(first: f.string(from: Date(timeIntervalSince1970: first)), more: fires.count - 1)
        }
        let wd = Rules.weekday(ds)
        return DayContent(date: ds, weekday: Self.weekdays[wd],
                          weekdayType: Rules.dayType(ds, isHoliday: isHoliday(ds)),
                          pay: pay, alarm: alarm, events: lines)
    }

    func weekContent(containing ds: String, today: String) -> WeekContent {
        let start = Rules.weekStart(of: ds, startMonday: startMonday)
        let days = (0..<7).map { Rules.addDays(start, $0) }
        let rows = SpanLayout.rows(events: store.visibleEvents, weekCells: days.map { Optional($0) })
        var bars: [WeekBar] = []
        for (lane, row) in rows.enumerated() where lane < 3 {
            for s in row {
                let ev = s.event
                let text = s.isStart ? (ev.barShowsTime ? Rules.timeLabel(ev) : ev.title) : "…"
                bars.append(WeekBar(id: ev.id + "-\(s.col)", col: s.col, span: s.span, lane: lane,
                                    text: text, color: ev.color, showsTime: s.isStart && ev.barShowsTime))
            }
        }
        let totals = store.totals(from: days[0], to: days[6], isHoliday: isHoliday)
        let hours = totals.reduce(0) { $0 + $1.hours }
        let pay = totals.reduce(0) { $0 + $1.pay }
        let s = Rules.ymd(days[0]), e = Rules.ymd(days[6])
        let title = s.month == e.month ? "\(s.month)月\(s.day)日〜\(e.day)日" : "\(s.month)月\(s.day)日〜\(e.month)月\(e.day)日"
        return WeekContent(title: title, days: days, dayNumbers: days.map { Rules.ymd($0).day },
                           dayTypes: days.map { Rules.dayType($0, isHoliday: isHoliday($0)) },
                           todayCol: days.firstIndex(of: today), bars: bars,
                           hours: Rules.formatHours(hours), pay: Money.yen(pay))
    }
}
