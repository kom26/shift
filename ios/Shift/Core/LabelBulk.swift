import Foundation

/// ラベルごとの予定の一覧と、まとめての付け替え・削除
extension Store {
    /// そのラベル(nil は「指定なし」)の通常予定。日付の古い順(日付のない予定は最後)
    func labelEvents(_ id: String?, oldestFirst: Bool = true) -> [ShiftEvent] {
        let list = events.filter { workplace(for: $0) == nil && $0.labelId == id }
        let key: (ShiftEvent) -> String = { ($0.startDate ?? "9999-99-99") + ($0.startTime ?? "") }
        return list.sorted { oldestFirst ? key($0) < key($1) : key($0) > key($1) }
    }
}
