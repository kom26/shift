import Foundation

enum BreakComparison: String, Codable {
    case atLeast  // 以上
    case over     // を超える
}

struct BreakRule: Codable, Equatable, Identifiable {
    var id: String
    var hours: Double
    var comparison: BreakComparison
    var minutes: Int
}

/// タイトルと色のプリセット + 給与設定。予定とは workplaceId(またはタイトル一致)で結びつく
struct Workplace: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var color: String
    var hourlyWage: Int
    var transport: Int
    var weekdayBonus: [Int]
    var holidayBonus: Int
    var breakRules: [BreakRule]
    var breakFromNight: Bool

    init(id: String, name: String, color: String,
         hourlyWage: Int = 0, transport: Int = 0,
         weekdayBonus: [Int] = [0, 0, 0, 0, 0, 0, 0],
         holidayBonus: Int = 0, breakRules: [BreakRule] = [],
         breakFromNight: Bool = true) {
        self.id = id
        self.name = name
        self.color = color
        self.hourlyWage = hourlyWage
        self.transport = transport
        self.weekdayBonus = Workplace.normalizedBonus(weekdayBonus)
        self.holidayBonus = holidayBonus
        self.breakRules = breakRules
        self.breakFromNight = breakFromNight
    }

    enum CodingKeys: String, CodingKey {
        case id, name, color, hourlyWage, transport, weekdayBonus, holidayBonus, breakRules, breakFromNight
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        color = try c.decode(String.self, forKey: .color)
        hourlyWage = try c.decodeIfPresent(Int.self, forKey: .hourlyWage) ?? 0
        transport = try c.decodeIfPresent(Int.self, forKey: .transport) ?? 0
        weekdayBonus = Workplace.normalizedBonus(try c.decodeIfPresent([Int].self, forKey: .weekdayBonus) ?? [])
        holidayBonus = try c.decodeIfPresent(Int.self, forKey: .holidayBonus) ?? 0
        breakRules = try c.decodeIfPresent([BreakRule].self, forKey: .breakRules) ?? []
        breakFromNight = try c.decodeIfPresent(Bool.self, forKey: .breakFromNight) ?? true
    }

    /// 7要素(0=日曜)に揃える
    private static func normalizedBonus(_ a: [Int]) -> [Int] {
        if a.count == 7 { return a }
        return Array((a + Array(repeating: 0, count: 7)).prefix(7))
    }
}
