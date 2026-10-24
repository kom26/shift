import Foundation

/// 休憩ルール編集行の入力(空文字を許す)
struct BreakRuleDraft: Identifiable, Equatable {
    var id: String = UUID().uuidString
    var hours: String = ""
    var minutes: String = ""
    var comparison: BreakComparison = .over

    init(id: String = UUID().uuidString, hours: String = "", minutes: String = "",
         comparison: BreakComparison = .over) {
        self.id = id
        self.hours = hours
        self.minutes = minutes
        self.comparison = comparison
    }

    init(rule: BreakRule) {
        let h = rule.hours
        self.init(id: rule.id,
                  hours: h == h.rounded() ? String(Int(h)) : String(h),
                  minutes: String(rule.minutes),
                  comparison: rule.comparison)
    }

    /// 空・不正な時間/分は 0 として扱う
    var rule: BreakRule? {
        let h = Double(hours.trimmingCharacters(in: .whitespaces)) ?? 0
        let m = Int(minutes.trimmingCharacters(in: .whitespaces)) ?? 0
        return BreakRule(id: id, hours: h, comparison: comparison, minutes: m)
    }

    /// 時間 0 かつ 分 0 の行(何も起きない行)は捨てる
    static func clean(_ drafts: [BreakRuleDraft]) -> [BreakRule] {
        drafts.compactMap { $0.rule }.filter { !($0.hours == 0 && $0.minutes == 0) }
    }

    static func clean(_ rows: [(hours: String, minutes: String)], comparison: BreakComparison) -> [BreakRule] {
        clean(rows.map { BreakRuleDraft(hours: $0.hours, minutes: $0.minutes, comparison: comparison) })
    }
}
