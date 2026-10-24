import Foundation

/// 時間が重なっている予定のある日を求める
enum Conflicts {
    private static func floorDiv(_ a: Int) -> Int {
        Int((Double(a) / 1440).rounded(.down))
    }

    /// 時刻つき・配置済みの予定同士が実時間で重なる、または間が minGapMinutes 分未満の日(yyyy-MM-dd)の集合。終日・未配置は無視する
    static func days(events: [ShiftEvent], minGapMinutes: Int = 0) -> Set<String> {
        var reference: String?
        var items: [(s: Int, e: Int)] = []
        for ev in events {
            guard ev.placed, !ev.allDay, let sd = ev.startDate, let sm = Rules.minutes(ev.startTime) else { continue }
            let ref = reference ?? sd
            reference = ref
            let base = Rules.daysBetween(ref, sd) * 1440
            let endDate = ev.endDate ?? sd
            var e = Rules.daysBetween(sd, endDate) * 1440 + (Rules.minutes(ev.endTime) ?? 1440)
            if e <= sm && endDate == sd { e = 1440 }
            items.append((base + sm, base + e))
        }
        guard let ref = reference, items.count > 1 else { return [] }
        items.sort { $0.s != $1.s ? $0.s < $1.s : $0.e < $1.e }
        var result = Set<String>()
        for i in 0..<items.count {
            var j = i + 1
            while j < items.count, items[j].s < items[i].e + minGapMinutes {
                let lo = max(items[i].s, items[j].s)
                let hi = min(items[i].e, items[j].e)
                let gap = items[j].s - items[i].e
                if gap >= 0 {
                    if gap < minGapMinutes {
                        for d in floorDiv(items[i].e)...floorDiv(items[j].s) { result.insert(Rules.addDays(ref, d)) }
                    }
                } else if lo < hi {
                    // 負の値にも対応するため切り下げ除算を使う
                    let first = Int((Double(lo) / 1440).rounded(.down))
                    let last = Int((Double(hi) / 1440).rounded(.up)) - 1
                    if first <= last {
                        for d in first...last { result.insert(Rules.addDays(ref, d)) }
                    }
                }
                j += 1
            }
        }
        return result
    }
}
