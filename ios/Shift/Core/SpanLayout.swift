import Foundation

struct BarSpan: Identifiable, Equatable {
    let event: ShiftEvent
    let col: Int
    let span: Int
    let isStart: Bool
    let isEnd: Bool
    var id: String { event.id }
}

enum SpanLayout {
    /// 1週間分の予定を、重ならないバーの行に詰める(Web版 computeWeekSpans 相当)
    static func rows(events: [ShiftEvent], weekCells: [String?]) -> [[BarSpan]] {
        let valid = weekCells.compactMap { $0 }
        guard let first = valid.first, let last = valid.last else { return [] }

        var spans: [BarSpan] = []
        for ev in events where ev.placed {
            guard let start = ev.startDate else { continue }
            let end = ev.endDate ?? start
            if start > last || end < first { continue }
            guard let cs = weekCells.firstIndex(where: { $0.map { $0 >= start } ?? false }) else { continue }
            let ce = weekCells.lastIndex(where: { $0.map { $0 <= end } ?? false }) ?? 6
            guard ce >= cs else { continue }
            spans.append(BarSpan(event: ev, col: cs, span: ce - cs + 1,
                                 isStart: start >= first && start <= last,
                                 isEnd: end >= first && end <= last))
        }

        // 同じ列は入力順を保つ(sort は安定ではないため添字で比較する)
        let sorted = spans.enumerated()
            .sorted { ($0.element.col, $0.offset) < ($1.element.col, $1.offset) }
            .map(\.element)

        var rows: [[BarSpan]] = []
        for s in sorted {
            let free = rows.firstIndex { row in
                !row.contains { $0.col < s.col + s.span && $0.col + $0.span > s.col }
            }
            if let free { rows[free].append(s) } else { rows.append([s]) }
        }
        return rows
    }
}
