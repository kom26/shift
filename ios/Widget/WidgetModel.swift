import Foundation

/// ウィジェットが表示に使う、ストア1つぶんの読み出し
struct WidgetSource {
    let store: Store
    let holidays: Holidays
    let startMonday: Bool
    let alarms: [AlarmEntry]
    let prefs: WidgetPrefs
    /// 共有カレンダーを見ているときの、その中身(予定者のアイコンに使う)
    var sharedCal: WidgetSharedCalendar?

    /// 労働時間・見込み給料の集計に使う入れ物。共有カレンダーを見ているときだけ、自分の職場(共有している分)で作る
    let workStore: Store?

    private static func tempStore() -> (store: Store, defaults: UserDefaults) {
        let name = "widget-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name) ?? .standard
        return (Store(fileURL: FileManager.default.temporaryDirectory.appending(path: name + ".json"), defaults: defaults), defaults)
    }

    /// アプリが書き出したデータから組み立てる。まだ書き出されていなければ空のカレンダー。
    /// prefs の calendarId が共有カレンダーなら、その中身を見る(アラームは自分のものなので出さない)
    static func load(prefs: WidgetPrefs = WidgetPrefs()) -> WidgetSource {
        let (store, defaults) = tempStore()
        let data = WidgetBridge.read()
        var alarms = data?.snapshot.alarms ?? []
        var workStore: Store?
        var sharedCal: WidgetSharedCalendar?
        if let id = prefs.calendarId {
            alarms = []
            if let cal = data?.shared?.first(where: { $0.id == id }) {
                sharedCal = cal
                store.applySnapshot(SyncSnapshot(events: cal.events, workplaces: [], favorites: [], customColors: [],
                                                 hiddenSuggestions: []))
                cal.anniversaries.forEach { store.saveAnniversary($0) }
                // 労働時間・見込み給料は、自分の職場のうち、この共有カレンダーに共有している分で集計する
                let ids = cal.sharedWorkplaceIds ?? []
                if let data, !ids.isEmpty {
                    let work = tempStore().store
                    work.applySnapshot(data.snapshot)
                    ids.forEach { work.toggleWorkplaceFilter($0) }
                    workStore = work
                }
            }
        } else {
            if let data { store.applySnapshot(data.snapshot) }
            prefs.workplaceIds.forEach { store.toggleWorkplaceFilter($0) }
            prefs.labelIds.forEach { store.toggleLabelFilter($0) }
        }
        return WidgetSource(store: store, holidays: Holidays(defaults: defaults),
                            startMonday: data?.startMonday ?? false, alarms: alarms, prefs: prefs, sharedCal: sharedCal,
                            workStore: workStore)
    }

    /// 労働時間・見込み給料を出せるか。自分のカレンダーなら職場が登録されているとき、共有カレンダーなら職場を共有しているとき
    var canShowWork: Bool { prefs.calendarId == nil ? !store.workplaces.isEmpty : workStore != nil }

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
    let isAllDay: Bool
    let showsTime: Bool
    /// 共有に出した予定の、共有した人のアイコン
    var owner: DayOwner?
    /// 共有カレンダーの中で作った予定の、共有カレンダーのアイコン(記号の名前、または "img:" + base64 の写真)
    var icon: String?
    /// 開始・締切の行のとき、開始(true)か締切(false)か。予定は nil
    var taskStart: Bool?
}

struct DayOwner: Equatable {
    let uid: String
    let name: String
    let avatar: String
}

/// 日付の横に出す、その日の記念日・誕生日のアイコン
struct DayAnnivIcon: Identifiable, Equatable {
    let id: String
    /// アプリと同じ画像の名前(Anniversary.Icon.asset)
    let asset: String
    let color: String
}

struct DayContent: Equatable {
    /// 日付の横に出す記念日アイコンの上限
    static let maxAnnivIcons = 4

    let date: String
    let weekday: String
    let weekdayType: DayType
    let pay: String?
    let alarm: DayAlarmBadge?
    let events: [DayEventLine]
    var annivs: [DayAnnivIcon] = []
    /// 共有カレンダーを見ているときの ID(タップで、そのカレンダーで開く)
    var calendarId: String?
    /// 右上の切り替えボタン(カレンダーを 2 つ以上選んでいるときだけ)
    var switcher: WidgetCalendarSwitch?
}

/// 右上の切り替えボタンに出す、いま見ているカレンダー
struct WidgetCalendarSwitch: Equatable {
    /// 共有カレンダーのアイコン(記号の名前、"記号|#色"、または "img:" + base64)。nil は自分のカレンダー
    let icon: String?
    /// 自分のカレンダーのとき、自分のプロフィールのアイコン(なければ、カレンダーの記号)
    var me: DayOwner? = nil
}

struct WeekBar: Identifiable, Equatable {
    let id: String
    let col: Int
    let span: Int
    let lane: Int
    let text: String
    let color: String
    let showsTime: Bool
    /// 開始・締切のタグのとき、開始(true)か締切(false)か。予定は nil。カレンダーと同じ矢印形で出す
    var taskStart: Bool? = nil
    /// 開始と締切を点線でつないだ 1 本のとき true。この週の中に、開始・締切のタグがあるか(なければ、その側は週の端まで点線)
    var link = false
    var showsStart = false
    var showsDue = false
}

struct WeekContent: Equatable {
    /// 予定のバーを並べる段の数(1 日に 5 件以上ある日は、3 段まで出して、4 段目に「ほか○件」)
    static let maxLanes = 4

    let title: String
    let days: [String]
    let dayNumbers: [Int]
    let dayTypes: [DayType]
    let todayCol: Int?
    let bars: [WeekBar]
    /// nil なら出さない(設定で消した)
    let hours: String?
    let pay: String?
    var calendarId: String?
    /// 右上の切り替えボタン(カレンダーを 2 つ以上選んでいるときだけ)
    var switcher: WidgetCalendarSwitch?
    /// 日ごとの印(記念日・誕生日、アラーム、給料日)。曜日の両脇に小さく出す。7 日ぶん(古い作りでは空)
    var marks: [WeekDayMarks] = []
    /// 日ごとの、出しきれなかった予定の数(「ほか○件」を、4 段目に出す)。7 日ぶん(0 なら出さない)
    var more: [Int] = []
}

/// 中(1週間)で出す、日ごとの印。日付の左にアラーム、右に給料日、日の列の右下に記念日・誕生日(2 個まで、3 個目からは「+n」)
struct WeekDayMarks: Equatable {
    var annivs: [DayAnnivIcon] = []
    /// 出しきれなかった記念日・誕生日の数(「+n」)
    var annivMore = 0
    var alarm = false
    var payday = false
}

/// ウィジェットのタップで開く、その日の予定一覧のリンク(共有カレンダーを見ているときは、そのカレンダーで開く)
func widgetDayURL(_ date: String, calendarId: String?) -> URL {
    let query = calendarId.map { "?cal=" + $0 } ?? ""
    return URL(string: "shiftpalette://day/\(date)\(query)") ?? URL(fileURLWithPath: "/")
}

extension WidgetSource {
    private static let weekdays = ["日", "月", "火", "水", "木", "金", "土"]

    func dayContent(_ ds: String) -> DayContent {
        let summary = store.daySummary(date: ds, isHoliday: isHoliday)
        // 並びは カレンダーと同じ順: ①前日からの予定 ②終日 ③時間予定(開始順)
        let carried = summary.events.filter { !$0.isAllDay && $0.isContinuation }
        let allDay = summary.events.filter { $0.isAllDay }
        let timed = summary.events.filter { !$0.isAllDay && !$0.isContinuation }
        let lines = (carried + allDay + timed).map { row -> DayEventLine in
            let ev = row.event
            let isCarried = !row.isAllDay && row.isContinuation
            let label = row.isAllDay ? "終日"
                : isCarried ? carriedLabel(ev, on: ds)
                : (ev.startTime == nil ? "" : Rules.timeLabel(ev))
            return DayEventLine(id: ev.id, title: ev.title, color: ev.color, label: label,
                                isAllDay: row.isAllDay, showsTime: !row.isAllDay && !isCarried && ev.startTime != nil,
                                owner: owner(of: ev.id), icon: calendarIcon(of: ev.id))
        }
        // 開始・締切(自分のカレンダーだけ。チェックを付けたものは出さない)。時刻のあるものは時刻順
        let taskLines = sharedCal != nil ? [] : store.taskRows(on: ds).filter { !$0.task.done }.map { row in
            DayEventLine(id: "task:" + row.id, title: row.task.title, color: row.task.color, label: row.time ?? "",
                         isAllDay: false, showsTime: row.time != nil, owner: nil, icon: nil, taskStart: row.isStart)
        }
        let paid = summary.paydays.reduce(0) { $0 + $1.amount }
        let pay = (summary.paydays.isEmpty || !prefs.showPayday) ? nil : Money.yen(paid)
        let fires = prefs.showAlarms ? alarms.filter { $0.date == ds }.map(\.fireTime).sorted() : []
        let alarm = fires.first.map { first -> DayAlarmBadge in
            let f = DateFormatter()
            f.dateFormat = "H:mm"
            return DayAlarmBadge(first: f.string(from: Date(timeIntervalSince1970: first)), more: fires.count - 1)
        }
        let wd = Rules.weekday(ds)
        var content = DayContent(date: ds, weekday: Self.weekdays[wd],
                          weekdayType: Rules.dayType(ds, isHoliday: isHoliday(ds)),
                          pay: pay, alarm: alarm, events: lines + taskLines,
                          annivs: store.anniversaries(on: ds)
                              .filter { $0.kind == .birthday ? prefs.showBirthdays : prefs.showAnniversaries }
                              .prefix(DayContent.maxAnnivIcons).map {
                              DayAnnivIcon(id: $0.id, asset: $0.icon.asset, color: $0.color)
                          })
        content.calendarId = prefs.calendarId
        return content
    }

    /// 共有した人のアイコン(共有カレンダーを見ていて、設定でオンのとき。共有カレンダーの中で作った予定は、出さない)
    private func owner(of eventId: String) -> DayOwner? {
        guard prefs.showOwnerIcons, let cal = sharedCal,
              let uid = cal.eventOwners?[eventId], let m = cal.members?[uid] else { return nil }
        return DayOwner(uid: uid, name: m.name, avatar: m.avatar)
    }

    /// 共有カレンダーのアイコン(共有カレンダーの中で作った予定だけ。設定でオンのとき)
    private func calendarIcon(of eventId: String) -> String? {
        guard prefs.showOwnerIcons, let cal = sharedCal, cal.eventOwners?[eventId] == nil, cal.eventOwners != nil,
              cal.events.contains(where: { $0.id == eventId }) else { return nil }
        return cal.icon ?? "person.2.fill"
    }

    /// 前の日から続く予定の表記。その日に終わるなら「前日から6:00」、まだ続くなら「前日から」
    private func carriedLabel(_ ev: ShiftEvent, on ds: String) -> String {
        let start = ev.startDate ?? ds
        let from: String
        if start == Rules.addDays(ds, -1) {
            from = "前日から"
        } else {
            let p = Rules.ymd(start)
            from = "\(p.month)/\(p.day)から"
        }
        if (ev.endDate ?? start) == ds, let end = ev.endTime { return from + end }
        return from
    }

    func weekContent(containing ds: String, today: String) -> WeekContent {
        let start = Rules.weekStart(of: ds, startMonday: startMonday)
        let days = (0..<7).map { Rules.addDays(start, $0) }
        // 開始・締切も、バーとして並べる(自分のカレンダーだけ)
        let taskBars = sharedCal != nil ? [] : store.taskMarkers(linked: true)
        let rows = SpanLayout.rows(events: store.visibleEvents + taskBars, weekCells: days.map { Optional($0) })
        // 1 日に 4 件までは、4 段で全部出す。5 件以上ある日は、3 段まで出して、4 段目に「ほか○件」を出す
        let maxLanes = WeekContent.maxLanes
        var total = Array(repeating: 0, count: 7)
        for row in rows { for s in row { for c in s.col..<min(7, s.col + s.span) { total[c] += 1 } } }
        var shown = Array(repeating: 0, count: 7)
        var lastLaneUsed = Array(repeating: false, count: 7)
        var bars: [WeekBar] = []
        for (lane, row) in rows.enumerated() where lane < maxLanes {
            for s in row {
                let cols = s.col..<min(7, s.col + s.span)
                // 4 段目は、「ほか○件」を出す日にかかるなら、出さない(その日の「ほか」に数える)
                if lane == maxLanes - 1, cols.contains(where: { total[$0] > maxLanes }) { continue }
                cols.forEach { shown[$0] += 1 }
                if lane == maxLanes - 1 { cols.forEach { lastLaneUsed[$0] = true } }
                let ev = s.event
                let mark = ev.taskMarker
                // 開始・締切は、カレンダーと同じ矢印形のタグで、タイトルを出す
                let isLink = mark?.isLink == true
                let text = (s.isStart || isLink) ? (mark != nil ? ev.title : (ev.barShowsTime ? Rules.timeLabel(ev) : ev.title)) : "…"
                bars.append(WeekBar(id: ev.id + "-\(s.col)", col: s.col, span: s.span, lane: lane,
                                    text: text, color: ev.color, showsTime: mark == nil && s.isStart && ev.barShowsTime,
                                    taskStart: isLink ? nil : mark?.isStart,
                                    link: isLink, showsStart: isLink && s.isStart, showsDue: isLink && s.isEnd))
            }
        }
        let totals = (workStore ?? store).totals(from: days[0], to: days[6], isHoliday: isHoliday)
        let hours = totals.reduce(0) { $0 + $1.hours }
        let pay = totals.reduce(0) { $0 + $1.pay }
        let s = Rules.ymd(days[0]), e = Rules.ymd(days[6])
        let title = s.month == e.month ? "\(s.month)月\(s.day)日〜\(e.day)日" : "\(s.month)月\(s.day)日〜\(e.month)月\(e.day)日"
        // 日ごとの印。アラームは自分のカレンダーだけ(共有カレンダーでは alarms が空)
        let marks = days.map { d -> WeekDayMarks in
            let all = store.anniversaries(on: d)
                .filter { $0.kind == .birthday ? prefs.showBirthdays : prefs.showAnniversaries }
            let annivs = all.prefix(2).map { DayAnnivIcon(id: $0.id, asset: $0.icon.asset, color: $0.color) }
            return WeekDayMarks(annivs: Array(annivs), annivMore: max(0, all.count - 2),
                                alarm: prefs.showAlarms && alarms.contains { $0.date == d },
                                payday: prefs.showPayday && !store.daySummary(date: d, isHoliday: isHoliday).paydays.isEmpty)
        }
        var content = WeekContent(title: title, days: days, dayNumbers: days.map { Rules.ymd($0).day },
                                  dayTypes: days.map { Rules.dayType($0, isHoliday: isHoliday($0)) },
                                  todayCol: days.firstIndex(of: today), bars: bars,
                                  hours: prefs.showHours && canShowWork ? Rules.formatHours(hours) : nil,
                                  pay: prefs.showEstimatedPay && canShowWork ? Money.yen(pay) : nil,
                                  calendarId: prefs.calendarId)
        content.marks = marks
        // 4 段目が空いている日だけ、出しきれなかった数を「ほか○件」で出す
        content.more = (0..<7).map { lastLaneUsed[$0] ? 0 : max(0, total[$0] - shown[$0]) }
        return content
    }
}
