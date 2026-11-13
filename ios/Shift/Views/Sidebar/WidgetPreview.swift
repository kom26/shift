import SwiftUI

/// ウィジェットの大きさの記号(ホーム画面のウィジェット追加で出るものと同じ形)。小は正方形、中は横長
struct WidgetSizeGlyph: View {
    let wide: Bool

    var body: some View {
        let w: CGFloat = wide ? 34 : 22
        let h: CGFloat = 22
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5).stroke(lineWidth: 2)
            RoundedRectangle(cornerRadius: 1.5).frame(width: 5, height: 5).offset(x: 4, y: 4)
            Capsule().frame(width: w - 10, height: 2).offset(x: 5, y: h - 7)
        }
        .frame(width: w, height: h)
    }
}

/// 設定画面の上に置く、ウィジェットのプレビュー。ウィジェットと同じ画面部品で描く。
/// ウィジェットの前へ・次へ・今日へ・切り替えのボタンは、プレビューの中でも押せる(それ以外の場所は、押しても何も起きない)
struct WidgetPreview: View {
    /// 0: 小 / 1: 中
    let size: Int
    let prefs: WidgetPrefs
    /// true: いま設定している内容での、本当の表示 / false: 仮の予定での表示イメージ
    let real: Bool
    /// 労働時間・見込み給料を出せるか(表示イメージのとき、出せないものは出さない)
    let workAvailable: Bool
    /// 右上の切り替えボタン(カレンダーを 2 つ以上選んでいるとき)
    var switcher: WidgetCalendarSwitch? = nil
    /// 今日(今週)からいくつ進めたか(前へ・次へのボタン)
    var offset = 0
    /// 切り替えで見ている位置(表示イメージで、カレンダーごとに中身を変える)
    var calendarIndex = 0
    var actions: WidgetPreviewActions? = nil

    private var width: CGFloat { size == 0 ? 158 : 338 }

    /// 表示イメージで、共有カレンダーに使う見本のアイコン(本当の共有カレンダーのアイコンは出さない)
    static let sampleIcons = ["heart.fill|#f28dae", "briefcase.fill|#3b82f6", "house.fill|#2c8a73", "star.fill|#e8890c"]
    static func sampleIcon(_ index: Int) -> String { sampleIcons[((index % 4) + 4) % 4] }

    /// 表示イメージの中身は、日付(週)を進めても、カレンダーを切り替えても変わる。4 通りでくり返す
    private var variant: Int { (((offset + calendarIndex) % 4) + 4) % 4 }

    var body: some View {
        content
            .frame(width: width, height: 158)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .environment(\.widgetPreviewActions, actions)
            // ウィジェットと同じく、端末の文字の大きさの設定に左右されないようにする
            .dynamicTypeSize(.large)
    }

    @ViewBuilder
    private var content: some View {
        if size == 0 {
            SmallDayView(content: dayContent(), offset: offset)
        } else {
            MediumWeekView(content: weekContent(), offset: offset)
        }
    }

    private func dayContent() -> DayContent {
        let date = Rules.addDays(Rules.today(), offset)
        var c = real ? WidgetSource.load(prefs: prefs).dayContent(date) : sampleDay(date)
        c.switcher = switcher
        return c
    }

    private func weekContent() -> WeekContent {
        let today = Rules.today()
        let anchor = Rules.addDays(today, 7 * offset)
        var c = real ? WidgetSource.load(prefs: prefs).weekContent(containing: anchor, today: today)
                     : sampleWeek(anchor, today: today)
        c.switcher = switcher
        return c
    }

    // MARK: 仮の予定(表示イメージ)

    private var isShared: Bool { prefs.calendarId != nil }

    /// 見本の予定 1 件。共有カレンダーでは、ほかの人の予定に人のアイコン、カレンダーの中で作った予定に見本のアイコン
    private func line(_ id: String, _ title: String, _ color: String, _ label: String, allDay: Bool = false,
                      byOther: Bool = false, inCalendar: Bool = false) -> DayEventLine {
        DayEventLine(id: id, title: title, color: color, label: label, isAllDay: allDay, showsTime: !allDay,
                     owner: isShared && byOther && prefs.showOwnerIcons ? DayOwner(uid: "sample", name: "あ", avatar: "") : nil,
                     icon: isShared && inCalendar && prefs.showOwnerIcons ? Self.sampleIcon(calendarIndex) : nil)
    }

    private func sampleDay(_ date: String) -> DayContent {
        let lines: [DayEventLine]
        switch variant {
        case 0:
            lines = [line("a", "早番", "#7a62d9", "9:00-17:00", byOther: true),
                     line("b", "ごはん", "#2c8a73", "19:00-21:00", inCalendar: true)]
        case 1:
            lines = [line("a", "遅番", "#e8890c", "13:00-22:00", byOther: true)]
        case 2:
            lines = [line("a", "休み", "#2c8a73", "終日", allDay: true),
                     line("b", "映画", "#d9695f", "18:30-21:00", inCalendar: true),
                     line("c", "ジム", "#3b82f6", "7:00-8:00", byOther: true)]
        default:
            lines = [line("a", "夜勤", "#a0785a", "22:00-6:30", byOther: true),
                     line("b", "歯医者", "#3b82f6", "10:30-11:00")]
        }
        var annivs: [DayAnnivIcon] = []
        if prefs.showBirthdays && (variant == 0 || variant == 2) {
            annivs.append(DayAnnivIcon(id: "bd", asset: Anniversary.Icon.cake.asset, color: "#e8890c"))
        }
        if prefs.showAnniversaries && (variant == 0 || variant == 3) {
            annivs.append(DayAnnivIcon(id: "an", asset: Anniversary.Icon.heart.asset, color: "#d9695f"))
        }
        let alarm = prefs.showAlarms && !isShared && (variant == 0 || variant == 3) ? DayAlarmBadge(first: "7:30", more: 0) : nil
        let pay = prefs.showPayday && !isShared && (variant == 1 || variant == 3) ? Money.yen(182_000) : nil
        var c = DayContent(date: date, weekday: ["日", "月", "火", "水", "木", "金", "土"][Rules.weekday(date)],
                           weekdayType: Rules.dayType(date, isHoliday: false),
                           pay: pay, alarm: alarm, events: lines, annivs: annivs)
        c.calendarId = prefs.calendarId
        return c
    }

    private func sampleWeek(_ anchor: String, today: String) -> WeekContent {
        let startMonday = UserDefaults.standard.bool(forKey: "startMonday")
        let start = Rules.weekStart(of: anchor, startMonday: startMonday)
        let days = (0..<7).map { Rules.addDays(start, $0) }
        let work = "#7a62d9"
        let bars: [WeekBar]
        switch variant {
        case 0:
            bars = [WeekBar(id: "1", col: 0, span: 1, lane: 0, text: "9:00-17:00", color: work, showsTime: true),
                    WeekBar(id: "2", col: 1, span: 2, lane: 0, text: "旅行", color: "#e8890c", showsTime: false),
                    WeekBar(id: "3", col: 3, span: 1, lane: 0, text: "9:00-17:00", color: work, showsTime: true),
                    WeekBar(id: "4", col: 1, span: 1, lane: 1, text: "ごはん", color: "#2c8a73", showsTime: false),
                    WeekBar(id: "5", col: 4, span: 1, lane: 1, text: "10:00-18:00", color: work, showsTime: true),
                    WeekBar(id: "6", col: 5, span: 2, lane: 0, text: "デート", color: "#d9695f", showsTime: false)]
        case 1:
            bars = [WeekBar(id: "1", col: 1, span: 1, lane: 0, text: "13:00-22:00", color: "#e8890c", showsTime: true),
                    WeekBar(id: "2", col: 2, span: 1, lane: 0, text: "13:00-22:00", color: "#e8890c", showsTime: true),
                    WeekBar(id: "3", col: 4, span: 1, lane: 0, text: "映画", color: "#d9695f", showsTime: false),
                    WeekBar(id: "4", col: 5, span: 1, lane: 0, text: "9:00-17:00", color: work, showsTime: true),
                    WeekBar(id: "5", col: 5, span: 1, lane: 1, text: "飲み会", color: "#3b82f6", showsTime: false)]
        case 2:
            bars = [WeekBar(id: "1", col: 0, span: 3, lane: 0, text: "合宿", color: "#2c8a73", showsTime: false),
                    WeekBar(id: "2", col: 3, span: 1, lane: 0, text: "7:00-16:00", color: work, showsTime: true),
                    WeekBar(id: "3", col: 4, span: 1, lane: 0, text: "7:00-16:00", color: work, showsTime: true),
                    WeekBar(id: "4", col: 4, span: 1, lane: 1, text: "歯医者", color: "#3b82f6", showsTime: false),
                    WeekBar(id: "5", col: 6, span: 1, lane: 0, text: "ライブ", color: "#d9695f", showsTime: false)]
        default:
            bars = [WeekBar(id: "1", col: 0, span: 1, lane: 0, text: "22:00-6:30", color: "#a0785a", showsTime: true),
                    WeekBar(id: "2", col: 2, span: 1, lane: 0, text: "22:00-6:30", color: "#a0785a", showsTime: true),
                    WeekBar(id: "3", col: 3, span: 1, lane: 0, text: "ランチ", color: "#e8890c", showsTime: false),
                    WeekBar(id: "4", col: 5, span: 2, lane: 0, text: "帰省", color: "#2c8a73", showsTime: false),
                    WeekBar(id: "5", col: 5, span: 1, lane: 1, text: "9:00-17:00", color: work, showsTime: true)]
        }
        let hours: [Double] = [32.5, 21, 27, 18.5]
        let pays: [Double] = [52_000, 33_600, 43_200, 31_450]
        var c = WeekContent(title: Self.title(days), days: days, dayNumbers: days.map { Rules.ymd($0).day },
                            dayTypes: days.map { Rules.dayType($0, isHoliday: false) },
                            todayCol: days.firstIndex(of: today), bars: bars,
                            hours: prefs.showHours && workAvailable ? Rules.formatHours(hours[variant]) : nil,
                            pay: prefs.showEstimatedPay && workAvailable ? Money.yen(pays[variant]) : nil,
                            calendarId: prefs.calendarId)
        // 日ごとの印(誕生日・記念日・アラーム・給料日)。オン・オフが分かるように、別々の日に置く(週ごとに位置を変える)
        var marks = Array(repeating: WeekDayMarks(), count: 7)
        if prefs.showBirthdays {
            marks[(1 + variant) % 7].annivs.append(DayAnnivIcon(id: "bd", asset: Anniversary.Icon.cake.asset, color: "#e8890c"))
        }
        if prefs.showAnniversaries {
            marks[(3 + variant) % 7].annivs.append(DayAnnivIcon(id: "an", asset: Anniversary.Icon.heart.asset, color: "#d9695f"))
        }
        if prefs.showAlarms && !isShared {
            marks[(2 + variant) % 7].alarm = true
            marks[(4 + variant) % 7].alarm = true
        }
        if prefs.showPayday && !isShared && variant != 2 { marks[(5 + variant) % 7].payday = true }
        c.marks = marks
        return c
    }

    private static func title(_ days: [String]) -> String {
        let s = Rules.ymd(days[0]), e = Rules.ymd(days[6])
        return s.month == e.month ? "\(s.month)月\(s.day)日〜\(e.day)日" : "\(s.month)月\(s.day)日〜\(e.month)月\(e.day)日"
    }
}
