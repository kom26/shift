import Foundation

/// ウィジェット 1 つの大きさ(小・中)ごとの設定。アプリの設定で決めて、ウィジェットに渡す
struct WidgetPrefs: Codable, Equatable {
    /// 見るカレンダー。nil は自分のカレンダー、それ以外は共有カレンダーの ID。
    /// 複数選んでいるときは、ウィジェットでいま見ているもの(viewing(_:) で決まる)。保存するときは calendarIds の先頭
    var calendarId: String?
    /// ウィジェット右上のボタンで、順に切り替えて見るカレンダー(選んだ順)。"" は自分のカレンダー。空にはしない
    var calendarIds: [String]
    /// 自分のカレンダーで、見せる職場(空なら全部)
    var workplaceIds: [String]
    /// 自分のカレンダーで、見せるラベル(空なら全部。「指定なし」は Store.noLabelKey)。
    /// 職場もラベルも 1 つも見せないときは、noneKey だけを入れる(空だと「全部」になってしまうため)
    var labelIds: [String]
    /// 自分のカレンダーで、開始・締切を見せるか
    var showTasks: Bool
    var showBirthdays: Bool
    var showAnniversaries: Bool
    var showAlarms: Bool
    var showPayday: Bool
    /// 中(週間)だけ
    var showHours: Bool
    var showEstimatedPay: Bool
    /// 小で共有カレンダーを見るとき、予定者のアイコンをバーの左に出す
    var showOwnerIcons: Bool

    init(calendarId: String? = nil, calendarIds: [String]? = nil, workplaceIds: [String] = [], labelIds: [String] = [],
         showBirthdays: Bool = true, showAnniversaries: Bool = true, showAlarms: Bool = true,
         showPayday: Bool = true, showHours: Bool = true, showEstimatedPay: Bool = true,
         showOwnerIcons: Bool = true, showTasks: Bool = true) {
        let ids = (calendarIds ?? []).isEmpty ? [calendarId ?? ""] : calendarIds!
        self.calendarIds = ids
        self.calendarId = ids[0].isEmpty ? nil : ids[0]
        self.workplaceIds = workplaceIds
        self.labelIds = labelIds
        self.showBirthdays = showBirthdays
        self.showAnniversaries = showAnniversaries
        self.showAlarms = showAlarms
        self.showPayday = showPayday
        self.showHours = showHours
        self.showEstimatedPay = showEstimatedPay
        self.showOwnerIcons = showOwnerIcons
        self.showTasks = showTasks
    }

    /// 職場もラベルも、1 つも見せないときの印(どの予定にも当てはまらない名前)
    static let noneKey = "~none"

    /// 項目が増えても、古い保存データを読めるようにする(無い項目は初期値)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // calendarIds が無い古いデータは、calendarId の 1 つだけ
        self.init(calendarId: try c.decodeIfPresent(String.self, forKey: .calendarId),
                  calendarIds: try c.decodeIfPresent([String].self, forKey: .calendarIds),
                  workplaceIds: try c.decodeIfPresent([String].self, forKey: .workplaceIds) ?? [],
                  labelIds: try c.decodeIfPresent([String].self, forKey: .labelIds) ?? [],
                  showBirthdays: try c.decodeIfPresent(Bool.self, forKey: .showBirthdays) ?? true,
                  showAnniversaries: try c.decodeIfPresent(Bool.self, forKey: .showAnniversaries) ?? true,
                  showAlarms: try c.decodeIfPresent(Bool.self, forKey: .showAlarms) ?? true,
                  showPayday: try c.decodeIfPresent(Bool.self, forKey: .showPayday) ?? true,
                  showHours: try c.decodeIfPresent(Bool.self, forKey: .showHours) ?? true,
                  showEstimatedPay: try c.decodeIfPresent(Bool.self, forKey: .showEstimatedPay) ?? true,
                  showOwnerIcons: try c.decodeIfPresent(Bool.self, forKey: .showOwnerIcons) ?? true,
                  showTasks: try c.decodeIfPresent(Bool.self, forKey: .showTasks) ?? true)
    }
}

extension WidgetPrefs {
    /// 切り替えで見るカレンダーが 2 つ以上あるか(ウィジェットの右上に切り替えボタンを出す)
    var canSwitch: Bool { calendarIds.count > 1 }

    /// 見ている位置を、カレンダーの数の中に収める(数が減っても、はみ出さない)
    func wrapped(_ index: Int) -> Int {
        let n = max(1, calendarIds.count)
        return ((index % n) + n) % n
    }

    /// index 番目のカレンダーを見るときの設定(calendarId を、そのカレンダーにする)
    func viewing(_ index: Int) -> WidgetPrefs {
        var p = self
        let id = calendarIds.isEmpty ? "" : calendarIds[wrapped(index)]
        p.calendarId = id.isEmpty ? nil : id
        return p
    }

    /// 切り替えで見るカレンダーを決める(空なら自分のカレンダーだけ)。calendarId は先頭にそろえる
    mutating func setCalendars(_ ids: [String]) {
        calendarIds = ids.isEmpty ? [""] : ids
        calendarId = calendarIds[0].isEmpty ? nil : calendarIds[0]
    }

    /// 選んでいる共有カレンダーの ID(自分のカレンダーは含まない)
    var sharedCalendarIds: [String] { calendarIds.filter { !$0.isEmpty } }

    /// 職場・ラベルで絞っていない(全部見せる)
    var showsAllKinds: Bool { workplaceIds.isEmpty && labelIds.isEmpty }

    /// その職場・ラベルを見せているか(絞っていなければ、全部見せている)
    func shows(_ id: String, workplace: Bool) -> Bool {
        showsAllKinds || (workplace ? workplaceIds : labelIds).contains(id)
    }

    /// 職場・ラベルを、見せる・見せないに切り替える。allWorkplaces・allLabels は、いまある全部(ラベルは「ラベルなし」も含む)。
    /// 全部見せることになったら、絞らない(空)に戻す。1 つも見せないことになったら noneKey を入れる
    mutating func toggleShown(_ id: String, workplace: Bool, allWorkplaces: [String], allLabels: [String]) {
        var w = showsAllKinds ? allWorkplaces : workplaceIds.filter { allWorkplaces.contains($0) }
        var l = showsAllKinds ? allLabels : labelIds.filter { allLabels.contains($0) }
        if workplace {
            if let i = w.firstIndex(of: id) { w.remove(at: i) } else { w.append(id) }
        } else {
            if let i = l.firstIndex(of: id) { l.remove(at: i) } else { l.append(id) }
        }
        if Set(w) == Set(allWorkplaces) && Set(l) == Set(allLabels) {
            w = []
            l = []
        } else if w.isEmpty && l.isEmpty {
            l = [Self.noneKey]
        }
        workplaceIds = w
        labelIds = l
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
