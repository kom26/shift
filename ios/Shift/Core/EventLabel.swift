import Foundation

/// 通常予定の分類。1 つの予定に付けられるのは 1 つだけ。勤務予定は職場がくくりなので付けない
/// (SwiftUI の Label と名前が衝突するので、型名は EventLabel)
struct EventLabel: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var color: String
}

extension EventLabel {
    /// 指定なし(職場もラベルも選ばない)の色(グレー)
    static let noneColor = Store.defaultColors[0]
}
