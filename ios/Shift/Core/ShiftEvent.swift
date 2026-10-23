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

    enum CodingKeys: String, CodingKey {
        case id, title, memo, color, startDate, endDate, placed, allDay, startTime, endTime, workHours
    }

    static func new(on date: String) -> ShiftEvent {
        ShiftEvent(id: UUID().uuidString, title: "", memo: "", color: "#6366f1",
                   startDate: date, endDate: date, placed: true, allDay: true,
                   startTime: nil, endTime: nil, workHours: nil)
    }

    var effectiveHours: Double? {
        workHours ?? Rules.workHours(start: startTime, end: endTime, allDay: allDay)
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
    }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let s = self, !s.isEmpty else { return nil }
        return s
    }
}
