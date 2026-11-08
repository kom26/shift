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

/// 設定画面の上に置く、ウィジェットのプレビュー。ウィジェットと同じ画面部品で描く
struct WidgetPreview: View {
    @Environment(CalendarService.self) private var calendarService
    /// 0: 小 / 1: 中
    let size: Int
    let prefs: WidgetPrefs
    /// true: いま設定している内容での、本当の表示 / false: 仮の予定でのイメージ
    let real: Bool
    /// 労働時間・見込み給料を出せるか(イメージのとき、出せないものは出さない)
    let workAvailable: Bool

    private var width: CGFloat { size == 0 ? 158 : 338 }

    var body: some View {
        content
            .frame(width: width, height: 158)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var content: some View {
        let today = Rules.today()
        if real {
            let source = WidgetSource.load(prefs: prefs)
            if size == 0 {
                SmallDayView(content: source.dayContent(today), offset: 0)
            } else {
                MediumWeekView(content: source.weekContent(containing: today, today: today), offset: 0)
            }
        } else if size == 0 {
            SmallDayView(content: sampleDay(today), offset: 0)
        } else {
            MediumWeekView(content: sampleWeek(today), offset: 0)
        }
    }

    // MARK: 仮の予定

    private var calendarIcon: String {
        calendarService.calendars.first { $0.id == prefs.calendarId }?.icon ?? "person.2.fill"
    }

    private func sampleDay(_ today: String) -> DayContent {
        let shared = prefs.calendarId != nil
        let lines = [
            DayEventLine(id: "a", title: "早番", color: "#7a62d9", label: "9:00-17:00", hours: "8:00",
                         isAllDay: false, showsTime: true,
                         owner: shared && prefs.showOwnerIcons ? DayOwner(uid: "sample", name: "あ", avatar: "") : nil),
            DayEventLine(id: "b", title: "ごはん", color: "#2c8a73", label: "19:00-21:00", hours: "",
                         isAllDay: false, showsTime: true,
                         icon: shared && prefs.showOwnerIcons ? calendarIcon : nil),
        ]
        var annivs: [DayAnnivIcon] = []
        if prefs.showBirthdays { annivs.append(DayAnnivIcon(id: "bd", symbol: "gift.fill", color: "#e8890c")) }
        if prefs.showAnniversaries { annivs.append(DayAnnivIcon(id: "an", symbol: "heart.fill", color: "#d9695f")) }
        let alarm = prefs.showAlarms && !shared ? DayAlarmBadge(first: "7:30", more: 0) : nil
        let pay = prefs.showPayday ? "給料日 " + Money.yen(182_000) : nil
        var c = DayContent(date: today, weekday: ["日", "月", "火", "水", "木", "金", "土"][Rules.weekday(today)],
                           weekdayType: Rules.dayType(today, isHoliday: false),
                           pay: pay, alarm: alarm, events: lines, annivs: annivs)
        c.calendarId = prefs.calendarId
        return c
    }

    private func sampleWeek(_ today: String) -> WeekContent {
        let startMonday = UserDefaults.standard.bool(forKey: "startMonday")
        let start = Rules.weekStart(of: today, startMonday: startMonday)
        let days = (0..<7).map { Rules.addDays(start, $0) }
        let bars = [
            WeekBar(id: "1", col: 0, span: 1, lane: 0, text: "9:00-17:00", color: "#7a62d9", showsTime: true),
            WeekBar(id: "2", col: 1, span: 2, lane: 0, text: "旅行", color: "#e8890c", showsTime: false),
            WeekBar(id: "3", col: 3, span: 1, lane: 0, text: "9:00-17:00", color: "#7a62d9", showsTime: true),
            WeekBar(id: "4", col: 1, span: 1, lane: 1, text: "ごはん", color: "#2c8a73", showsTime: false),
            WeekBar(id: "5", col: 4, span: 1, lane: 1, text: "10:00-18:00", color: "#7a62d9", showsTime: true),
            WeekBar(id: "6", col: 5, span: 2, lane: 0, text: "デート", color: "#d9695f", showsTime: false),
        ]
        return WeekContent(title: Self.title(days), days: days, dayNumbers: days.map { Rules.ymd($0).day },
                           dayTypes: days.map { Rules.dayType($0, isHoliday: false) },
                           todayCol: days.firstIndex(of: today), bars: bars,
                           hours: prefs.showHours && workAvailable ? Rules.formatHours(32.5) : nil,
                           pay: prefs.showEstimatedPay && workAvailable ? Money.yen(52_000) : nil,
                           calendarId: prefs.calendarId)
    }

    private static func title(_ days: [String]) -> String {
        let s = Rules.ymd(days[0]), e = Rules.ymd(days[6])
        return s.month == e.month ? "\(s.month)月\(s.day)日〜\(e.day)日" : "\(s.month)月\(s.day)日〜\(e.month)月\(e.day)日"
    }
}
