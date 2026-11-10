import Foundation

/// ラベルごとの予定の一覧と、まとめての付け替え・削除
extension Store {
    /// そのラベル(nil は「指定なし」)の通常予定。日付の古い順(日付のない予定は最後)
    func labelEvents(_ id: String?, oldestFirst: Bool = true) -> [ShiftEvent] {
        let list = events.filter { workplace(for: $0) == nil && $0.labelId == id }
        let key: (ShiftEvent) -> String = { ($0.startDate ?? "9999-99-99") + ($0.startTime ?? "") }
        return list.sorted { oldestFirst ? key($0) < key($1) : key($0) > key($1) }
    }

    /// 選んだ予定のラベルをまとめて変える(nil は「指定なし」)。個別カラーでない予定は、新しいラベルの色に付いていく
    func setLabel(eventIds: Set<String>, to labelId: String?) {
        let newColor = label(for: labelId)?.color ?? EventLabel.noneColor
        var touched = false
        for i in events.indices where eventIds.contains(events[i].id) && workplace(for: events[i]) == nil {
            let oldColor = label(for: events[i].labelId)?.color ?? EventLabel.noneColor
            var e = events[i]
            if e.ownColor != true, e.color == oldColor { e.color = newColor }
            e.labelId = labelId
            events[i] = stamped(e)
            touched = true
        }
        if touched { persist() }
    }

    /// 選んだ予定をまとめて消す
    func deleteEvents(ids: Set<String>) {
        guard events.contains(where: { ids.contains($0.id) }) else { return }
        events.removeAll { ids.contains($0.id) }
        persist()
    }
}
