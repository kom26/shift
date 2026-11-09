import Foundation

struct ShiftEvent: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var memo: String
    var color: String
    var startDate: String?
    var endDate: String?
    var placed: Bool
    var allDay: Bool
    var startTime: String?
    var endTime: String?
    var workHours: Double?
    var workplaceId: String? = nil
    var breakInNight: Bool? = nil
    /// バーに予定名を出すか。nil/false は時間(終日と時間未設定の予定は、いつも予定名)
    var barShowsTitle: Bool? = nil
    /// 一律加給・調整給(円)。手入力で、nil は 0 円
    var adjustment: Int? = nil
    /// 日給の職場での、その予定の日給(円・手入力)
    var dailyWage: Int? = nil
    /// 通常予定のラベル(1 つだけ)。nil は「指定なし」。勤務予定には付けない
    var labelId: String? = nil
    /// 個別カラー。true はこの予定の色、nil・false は職場やラベルの色に付いていく
    var ownColor: Bool? = nil
    /// 最後に変えた時刻(Unix 秒)と、変えた人の名前。編集画面の下に出す(古い予定は nil)
    var updatedAt: Double? = nil
    var updatedBy: String? = nil
    /// 作り方の印。"screenshot" は、画像取り込みで作った予定
    var source: String? = nil

    static let screenshotSource = "screenshot"

    enum CodingKeys: String, CodingKey {
        case id, title, memo, color, startDate, endDate, placed, allDay, startTime, endTime, workHours, workplaceId, breakInNight, barShowsTitle, adjustment, dailyWage, labelId, ownColor, updatedAt, updatedBy, source
    }

    /// 以前のレイヤー(複数)。読むだけで、書き出さない
    private enum LegacyKeys: String, CodingKey {
        case layerIds
    }

    static func new(on date: String) -> ShiftEvent {
        ShiftEvent(id: UUID().uuidString, title: "", memo: "", color: Store.defaultColors[0],
                   startDate: date, endDate: date, placed: true, allDay: false,
                   startTime: nil, endTime: nil, workHours: nil)
    }

    static func newUnplaced() -> ShiftEvent {
        ShiftEvent(id: UUID().uuidString, title: "", memo: "", color: Store.defaultColors[0],
                   startDate: nil, endDate: nil, placed: false, allDay: false,
                   startTime: nil, endTime: nil, workHours: nil)
    }

    var effectiveHours: Double? {
        workHours ?? Rules.workHours(startDate: startDate, startTime: startTime, endDate: endDate, endTime: endTime, allDay: allDay)
    }
}

extension ShiftEvent {
    /// 編集画面の下に出す「最終変更」の文(変更した記録がない予定は nil)。画像取り込みで作った予定には、その印を添える
    func lastModifiedText(calendar: Calendar = .current) -> String? {
        guard let at = updatedAt else { return nil }
        let d = Date(timeIntervalSince1970: at)
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        let when = String(format: "%d年%d月%d日 %d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
        let who = (updatedBy?.isEmpty == false) ? updatedBy! : "自分"
        return "- 最終変更\(when) ・\(who)" + (source == Self.screenshotSource ? "(画像取り込み)" : "") + " -"
    }

    /// Web版のJSONは項目が欠けていることがあるため、欠落は既定値で補う
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        memo = try c.decodeIfPresent(String.self, forKey: .memo) ?? ""
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "#6366f1"
        startDate = try c.decodeIfPresent(String.self, forKey: .startDate).nonEmpty
        endDate = try c.decodeIfPresent(String.self, forKey: .endDate).nonEmpty
        placed = try c.decodeIfPresent(Bool.self, forKey: .placed) ?? (startDate != nil)
        allDay = try c.decodeIfPresent(Bool.self, forKey: .allDay) ?? true
        startTime = try c.decodeIfPresent(String.self, forKey: .startTime).nonEmpty
        endTime = try c.decodeIfPresent(String.self, forKey: .endTime).nonEmpty
        workHours = try c.decodeIfPresent(Double.self, forKey: .workHours)
        workplaceId = try c.decodeIfPresent(String.self, forKey: .workplaceId)
        breakInNight = try c.decodeIfPresent(Bool.self, forKey: .breakInNight)
        barShowsTitle = try c.decodeIfPresent(Bool.self, forKey: .barShowsTitle)
        adjustment = try c.decodeIfPresent(Int.self, forKey: .adjustment)
        dailyWage = try c.decodeIfPresent(Int.self, forKey: .dailyWage)
        ownColor = try c.decodeIfPresent(Bool.self, forKey: .ownColor)
        updatedAt = try c.decodeIfPresent(Double.self, forKey: .updatedAt)
        updatedBy = try c.decodeIfPresent(String.self, forKey: .updatedBy)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        if let l = try c.decodeIfPresent(String.self, forKey: .labelId) {
            labelId = l
        } else if workplaceId == nil {
            // レイヤーは、通常予定だけ最初の 1 つをラベルに引き継ぐ("mine" は「指定なし」)
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            labelId = try legacy.decodeIfPresent([String].self, forKey: .layerIds)?.first { $0 != "mine" }
        }
    }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let s = self, !s.isEmpty else { return nil }
        return s
    }
}

extension ShiftEvent {
    /// 時間つき(終日でなく開始時刻がある)か。週ビューのドロップ表示の出し分けに使う
    var isTimedDrop: Bool { !allDay && startTime != nil }

    /// カレンダーのバーに出す文字
    var barLabel: String { barShowsTime ? Rules.timeLabel(self) : title }

    /// バーに時間を出すか(終日と時間未設定は予定名)
    var barShowsTime: Bool { !(allDay || startTime == nil || barShowsTitle == true) }
}
