import Foundation

/// アプリがウィジェットに渡すデータ。ウィジェットは読むだけで、元のデータには触らない
struct WidgetData: Codable, Equatable {
    var snapshot: SyncSnapshot
    var startMonday: Bool
    /// 小・中それぞれの設定(古いデータには無いので省略可)
    var small: WidgetPrefs?
    var medium: WidgetPrefs?
    /// ウィジェットで見る共有カレンダーの中身(アプリを開いたときに取ってくる)
    var shared: [WidgetSharedCalendar]?
    /// 開始と締切を点線でつなぐか(設定。古いデータには無いので省略可。なければ、つながない)
    var linkTasks: Bool?
}

/// ウィジェットに渡す、共有カレンダー 1 つぶんの予定と誕生日・記念日
struct WidgetSharedCalendar: Codable, Equatable {
    var id: String
    var name: String
    /// 共有カレンダーのアイコン(記号の名前、または "img:" + base64 の写真)。古いデータには無いので省略可
    var icon: String?
    var events: [ShiftEvent]
    var anniversaries: [Anniversary]
    /// この共有カレンダーに、自分が共有している職場(労働時間・見込み給料の集計に使う)。古いデータには無いので省略可
    var sharedWorkplaceIds: [String]?
    /// 予定の ID → 予定者の uid(予定者のアイコンを出すのに使う。共有カレンダーの中で作った予定は含まない)。古いデータには無いので省略可
    var eventOwners: [String: String]?
    /// 参加者の uid → 名前とアバター
    var members: [String: WidgetMember]?
}

struct WidgetMember: Codable, Equatable {
    var name: String
    var avatar: String
}

/// アプリとウィジェットが App Group の共有領域でやり取りする
enum WidgetBridge {
    static let groupId = "group.com.kom26.shift"
    /// 小・中を同じウィジェットにまとめる(右下をドラッグして大きさを切り替えられるように)
    static let kind = "ShiftWidget"

    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId)?
            .appending(path: "widget-data.json")
    }

    static var defaults: UserDefaults? { UserDefaults(suiteName: groupId) }

    static func write(_ data: WidgetData) {
        guard let url = fileURL, let encoded = try? JSONEncoder().encode(data) else { return }
        try? encoded.write(to: url, options: .atomic)
    }

    static func read() -> WidgetData? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetData.self, from: data)
    }
}

/// ウィジェットで「前へ・次へ」を押したときの表示位置。押した日だけ有効で、日付が変わると今日に戻る
struct WidgetOffset {
    let key: String
    var defaults: UserDefaults? = WidgetBridge.defaults

    private var valueKey: String { key + ".offset" }
    private var dayKey: String { key + ".day" }

    func current(today: String = Rules.today()) -> Int {
        guard let defaults, defaults.string(forKey: dayKey) == today else { return 0 }
        return defaults.integer(forKey: valueKey)
    }

    func set(_ value: Int, today: String = Rules.today()) {
        defaults?.set(value, forKey: valueKey)
        defaults?.set(today, forKey: dayKey)
    }

    func step(_ delta: Int, today: String = Rules.today()) {
        set(current(today: today) + delta, today: today)
    }
}
