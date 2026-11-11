import Foundation

/// 予定バーの設定のプレビューに使う、架空の予定。予定が入っていなくても、見た目を確かめられる。
/// 今月の週ごとに、2 種類のひな形を交互に入れる(自分の予定には、触れない)
enum BarSample {
    private struct Item {
        let col: Int
        let span: Int
        let title: String
        let color: String
        /// nil は終日(タイトルのバー)。"9:00-17:00" のような時間があれば、時間のバー
        let time: (start: String, end: String)?
    }

    private static let purple = "#7a62d9", green = "#2f9e6a", orange = "#d98a1f", pink = "#d94f7a", blue = "#2f6fed"

    private static let even: [Item] = [
        Item(col: 0, span: 3, title: "研修", color: purple, time: nil),
        Item(col: 1, span: 1, title: "早番", color: green, time: ("9:00", "17:00")),
        Item(col: 3, span: 1, title: "歯医者", color: pink, time: nil),
        Item(col: 4, span: 1, title: "会議", color: orange, time: ("10:00", "18:00")),
        Item(col: 5, span: 1, title: "ごはん", color: blue, time: nil),
        Item(col: 0, span: 1, title: "夜勤", color: green, time: ("17:00", "21:00")),
        Item(col: 2, span: 1, title: "面談", color: orange, time: ("13:00", "18:00")),
        Item(col: 6, span: 1, title: "映画", color: pink, time: ("15:00", "22:00")),
    ]

    private static let odd: [Item] = [
        Item(col: 0, span: 1, title: "早番", color: green, time: ("9:00", "17:00")),
        Item(col: 2, span: 3, title: "出張", color: blue, time: nil),
        Item(col: 5, span: 2, title: "旅行", color: pink, time: nil),
        Item(col: 1, span: 1, title: "勉強会", color: purple, time: ("19:00", "21:00")),
        Item(col: 3, span: 1, title: "歯医者", color: pink, time: ("9:00", "12:00")),
        Item(col: 5, span: 1, title: "会議", color: orange, time: ("8:00", "12:00")),
    ]

    /// 今月(週の始まりは設定に合わせる)の週ごとに、予定を入れた仮のストア。ファイルは、一時フォルダに作る
    static func store(startMonday: Bool, today: String = Rules.today()) -> Store {
        let name = "bar-sample-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name) ?? .standard
        let store = Store(fileURL: FileManager.default.temporaryDirectory.appending(path: name + ".json"), defaults: defaults)
        let p = Rules.ymd(today)
        let weeks = Rules.monthGrid(year: p.year, month: p.month, startMonday: startMonday)
        for (w, days) in weeks.enumerated() {
            for (i, item) in (w % 2 == 0 ? even : odd).enumerated() {
                let start = days[item.col]
                let end = days[min(6, item.col + item.span - 1)]
                var e = ShiftEvent.new(on: start)
                e.id = "sample-\(w)-\(i)"
                e.title = item.title
                e.color = item.color
                e.ownColor = true
                e.endDate = end
                if let t = item.time {
                    e.allDay = false
                    e.startTime = t.start
                    e.endTime = t.end
                    e.barShowsTitle = nil
                } else {
                    e.allDay = true
                    e.barShowsTitle = true
                }
                store.save(e)
            }
        }
        return store
    }
}
