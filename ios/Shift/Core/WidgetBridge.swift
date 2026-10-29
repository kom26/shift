import Foundation

/// アプリがウィジェットに渡すデータ。ウィジェットは読むだけで、元のデータには触らない
struct WidgetData: Codable, Equatable {
    var snapshot: SyncSnapshot
    var startMonday: Bool
}

/// アプリとウィジェットが App Group の共有領域でやり取りする
enum WidgetBridge {
    static let groupId = "group.com.kom26.shift"
    static let dayKind = "ShiftDayWidget"
    static let weekKind = "ShiftWeekWidget"

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
