import Foundation

/// 週表示の列に出す、時刻の印(アラーム・開始・締切)の並べ方。
/// 近い印(前の印との差が 1 時間以内)は 1 つの組にして、通常の予定と同じように、列の幅を分け合う。
/// 同じ種類の印は 1 つにまとめて、数を「+n」で添える。なので、1 つの組は最大 3 分割
enum WeekMarkerLayout {
    /// 並びは、左から アラーム・開始・締切
    enum Kind: Int, CaseIterable { case bell, start, due }

    struct Item: Equatable {
        let kind: Kind
        /// その日の 0 時からの分
        let minutes: Int
        /// 開始・締切の色。アラームは nil
        let color: String?
    }

    struct Slot: Equatable {
        let kind: Kind
        let minutes: Int
        let color: String?
        /// 組の中で左から何番目か、組が何分割か
        let slot: Int
        let count: Int
        /// まとめた、ほかの印の数(「+n」の n)
        let extra: Int
    }

    /// 近いとみなす差(分。この値ちょうどを含む)
    static let nearMinutes = 60

    static func layout(_ items: [Item]) -> [Slot] {
        let sorted = items.sorted { ($0.minutes, $0.kind.rawValue) < ($1.minutes, $1.kind.rawValue) }
        var groups: [[Item]] = []
        for item in sorted {
            if let last = groups.last?.last, item.minutes - last.minutes <= nearMinutes {
                groups[groups.count - 1].append(item)
            } else {
                groups.append([item])
            }
        }
        var out: [Slot] = []
        for group in groups {
            let kinds = Kind.allCases.filter { k in group.contains { $0.kind == k } }
            for (i, kind) in kinds.enumerated() {
                let same = group.filter { $0.kind == kind }
                // いちばん早い 1 つを描いて、残りは「+n」に数える
                out.append(Slot(kind: kind, minutes: same[0].minutes, color: same[0].color,
                                slot: i, count: kinds.count, extra: same.count - 1))
            }
        }
        return out
    }
}
