import Foundation

/// 共有カレンダーで、24時をこえる予定をどう見せるか(この端末の、その共有カレンダーだけ)。
/// nil は「予定作成者の表示のまま」。予定の中身は変えず、表示用の予定だけを書きかえる
struct OvernightDisplay: Codable, Equatable {
    /// 日付をまたぐ予定(22:00〜翌6:00 / 22:00〜30:00)
    var lateEnd: LateEndChoice?
    /// 開始が24時以降の予定(24:00〜30:00 など)
    var afterMidnight: AfterMidnightChoice?

    var isDefault: Bool { lateEnd == nil && afterMidnight == nil }

    /// 表示する形にした予定。当てはまらない予定(終日・未配置・24時をこえない・3日以上の予定など)は、そのまま
    func apply(_ ev: ShiftEvent) -> ShiftEvent {
        guard !isDefault, ev.placed, !ev.allDay, let sd = ev.startDate,
              let s = Rules.minutes(ev.startTime), let e = Rules.minutes(ev.endTime) else { return ev }
        let days = Rules.daysBetween(sd, ev.endDate ?? sd)
        guard days == 0 || days == 1 else { return ev }
        // 始まった日の 0:00 から数えた、終わりの時刻(分)
        var end = days * 1440 + e
        guard end > s else { return ev }
        var out = ev
        if s >= 1440 {
            guard let choice = afterMidnight else { return ev }
            switch choice {
            case .keep:
                // 24:00〜30:00 のまま(始まった日に収める)
                guard end <= 2880 else { return ev }
                out.endDate = sd
                out.endTime = Self.text(end)
            case .cross:
                // 24:00〜翌6:00
                guard end > 1440 else { return ev }
                out.endDate = Rules.addDays(sd, 1)
                out.endTime = Self.text(end - 1440)
            case .next:
                // 翌日の 0:00〜6:00
                let next = Rules.addDays(sd, 1)
                end -= 1440
                out.startDate = next
                out.startTime = Self.text(s - 1440)
                if end <= 1440 {
                    out.endDate = next
                    out.endTime = Self.text(end)
                } else {
                    out.endDate = Rules.addDays(next, 1)
                    out.endTime = Self.text(end - 1440)
                }
            }
        } else {
            // 開始は24時前で、24時をこえて終わる予定だけ
            guard end > 1440, let choice = lateEnd else { return ev }
            switch choice {
            case .fit:
                // 22:00〜30:00(36:00 までなら、その日に収める)
                guard end <= 2160 else { return ev }
                out.endDate = sd
                out.endTime = Self.text(end)
            case .cross:
                // 22:00〜翌6:00
                out.endDate = Rules.addDays(sd, 1)
                out.endTime = Self.text(end - 1440)
            }
        }
        return out
    }

    private static func text(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    // MARK: 保存(この端末だけ。共有カレンダーの ID ごと)

    static let defaultsKey = "shared-overnight-display"

    static func loadAll(defaults: UserDefaults) -> [String: OvernightDisplay] {
        defaults.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode([String: OvernightDisplay].self, from: $0) } ?? [:]
    }

    static func load(_ calendarId: String, defaults: UserDefaults) -> OvernightDisplay {
        loadAll(defaults: defaults)[calendarId] ?? OvernightDisplay()
    }

    static func save(_ value: OvernightDisplay, for calendarId: String, defaults: UserDefaults) {
        var all = loadAll(defaults: defaults)
        all[calendarId] = value.isDefault ? nil : value
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: defaultsKey) }
    }
}
