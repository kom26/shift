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

    enum CodingKeys: String, CodingKey {
        case id, title, memo, color, startDate, endDate, placed, allDay, startTime, endTime, workHours, workplaceId, breakInNight, barShowsTitle
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
    var barLabel: String {
        (allDay || startTime == nil || barShowsTitle == true) ? title : Rules.timeLabel(self)
    }
}
