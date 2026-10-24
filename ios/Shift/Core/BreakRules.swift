import Foundation

enum BreakRules {
    /// span = 拘束時間(分)。rules が空なら法定(480超→60、360超→45)
    static func minutes(span: Int, rules: [BreakRule]) -> Int {
        if rules.isEmpty {
            return span > 480 ? 60 : span > 360 ? 45 : 0
        }
        var best: (hours: Double, minutes: Int)?
        for r in rules {
            let t = r.hours * 60
            let ok: Bool
            switch r.comparison {
            case .atLeast: ok = Double(span) >= t
            case .over: ok = Double(span) > t
            }
            guard ok else { continue }
            // しきい値が同じなら後ろのルールを採用(>=)
            if best == nil || r.hours >= best!.hours { best = (r.hours, r.minutes) }
        }
        return best?.minutes ?? 0
    }
}
