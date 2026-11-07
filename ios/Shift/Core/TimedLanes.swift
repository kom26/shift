import Foundation

/// 週表示の 1 日の列で、時間が重なる予定を、横に分けて並べるための割り当て。
/// 重なっている予定のまとまりごとに、同じ列数で等分する(重なっていない予定は、幅いっぱい)
enum TimedLanes {
    struct Item {
        let id: String
        /// 1 日の中での位置(0〜1)
        let top: Double
        let bottom: Double
    }

    struct Slot: Equatable {
        let lane: Int
        let count: Int
    }

    static func assign(_ items: [Item]) -> [String: Slot] {
        let sorted = items.sorted { ($0.top, $0.bottom, $0.id) < ($1.top, $1.bottom, $1.id) }
        var result: [String: Slot] = [:]
        var cluster: [(item: Item, lane: Int)] = []
        var laneEnds: [Double] = []
        var clusterEnd = -Double.infinity

        func flush() {
            let count = max(1, laneEnds.count)
            for c in cluster { result[c.item.id] = Slot(lane: c.lane, count: count) }
            cluster = []
            laneEnds = []
        }

        for it in sorted {
            // 前のまとまりと重ならないなら、そこで区切る
            if !cluster.isEmpty, it.top >= clusterEnd { flush() }
            let lane = laneEnds.firstIndex { $0 <= it.top } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(it.bottom) } else { laneEnds[lane] = it.bottom }
            cluster.append((it, lane))
            clusterEnd = cluster.count == 1 ? it.bottom : max(clusterEnd, it.bottom)
        }
        flush()
        return result
    }
}
