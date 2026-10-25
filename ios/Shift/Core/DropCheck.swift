import Foundation

/// ドラッグ中の配置先で、時間つきの他の予定と時間が重なるかの判定
enum DropCheck {
    /// ref の 0:00 からの絶対分 [s, e)。時刻つき・配置済み・終日でない予定のみ
    private static func interval(_ ev: ShiftEvent, ref: String) -> (s: Int, e: Int)? {
        guard ev.placed, !ev.allDay, let sd = ev.startDate, let sm = Rules.minutes(ev.startTime) else { return nil }
        let endDate = ev.endDate ?? sd
        var e = Rules.daysBetween(sd, endDate) * 1440 + (Rules.minutes(ev.endTime) ?? 1440)
        if e <= sm && endDate == sd { e = 1440 }
        let base = Rules.daysBetween(ref, sd) * 1440
        return (base + sm, base + e)
    }

    /// moved(移動後の姿)が、others のうち時刻つきの予定と実時間で重なれば true
    static func overlaps(moved: ShiftEvent, others: [ShiftEvent]) -> Bool {
        guard let sd = moved.startDate, let m = interval(moved, ref: sd) else { return false }
        for o in others where o.id != moved.id {
            guard let t = interval(o, ref: sd) else { continue }
            if max(m.s, t.s) < min(m.e, t.e) { return true }
        }
        return false
    }
}
