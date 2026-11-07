import Foundation

/// ウィジェット 1 つの大きさ(小・中)ごとの設定。アプリの設定で決めて、ウィジェットに渡す
struct WidgetPrefs: Codable, Equatable {
    /// 見るカレンダー。nil は自分のカレンダー、それ以外は共有カレンダーの ID
    var calendarId: String?
    /// 自分のカレンダーで、見せる職場(空なら全部)
    var workplaceIds: [String]
    /// 自分のカレンダーで、見せるラベル(空なら全部。「指定なし」は Store.noLabelKey)
    var labelIds: [String]
    var showBirthdays: Bool
    var showAnniversaries: Bool
    var showAlarms: Bool
    var showPayday: Bool
    /// 中(週間)だけ
    var showHours: Bool
    var showEstimatedPay: Bool

    init(calendarId: String? = nil, workplaceIds: [String] = [], labelIds: [String] = [],
         showBirthdays: Bool = true, showAnniversaries: Bool = true, showAlarms: Bool = true,
         showPayday: Bool = true, showHours: Bool = true, showEstimatedPay: Bool = true) {
        self.calendarId = calendarId
        self.workplaceIds = workplaceIds
        self.labelIds = labelIds
        self.showBirthdays = showBirthdays
        self.showAnniversaries = showAnniversaries
        self.showAlarms = showAlarms
        self.showPayday = showPayday
        self.showHours = showHours
        self.showEstimatedPay = showEstimatedPay
    }

    /// 項目が増えても、古い保存データを読めるようにする(無い項目は初期値)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(calendarId: try c.decodeIfPresent(String.self, forKey: .calendarId),
                  workplaceIds: try c.decodeIfPresent([String].self, forKey: .workplaceIds) ?? [],
                  labelIds: try c.decodeIfPresent([String].self, forKey: .labelIds) ?? [],
                  showBirthdays: try c.decodeIfPresent(Bool.self, forKey: .showBirthdays) ?? true,
                  showAnniversaries: try c.decodeIfPresent(Bool.self, forKey: .showAnniversaries) ?? true,
                  showAlarms: try c.decodeIfPresent(Bool.self, forKey: .showAlarms) ?? true,
                  showPayday: try c.decodeIfPresent(Bool.self, forKey: .showPayday) ?? true,
                  showHours: try c.decodeIfPresent(Bool.self, forKey: .showHours) ?? true,
                  showEstimatedPay: try c.decodeIfPresent(Bool.self, forKey: .showEstimatedPay) ?? true)
    }
}

enum WidgetPrefsKey {
    static let small = "widget-prefs-small"
    static let medium = "widget-prefs-medium"
}

extension WidgetPrefs {
    static func load(_ key: String, defaults: UserDefaults = .standard) -> WidgetPrefs {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(WidgetPrefs.self, from: $0) } ?? WidgetPrefs()
    }

    func save(_ key: String, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: key) }
    }
}
