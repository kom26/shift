import Foundation

/// 予定を分類する単位。1 つの予定は複数のレイヤーに入れられる
struct Layer: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var color: String

    /// 標準のレイヤー。レイヤーを選んでいない予定は、ここに入る(削除・名前変更はできない)
    static let mineId = "mine"
    static let mine = Layer(id: mineId, name: "自分の予定", color: "#bec1cc")
}

extension ShiftEvent {
    /// 入っているレイヤー。何も選んでいなければ「自分の予定」
    var effectiveLayerIds: [String] {
        let ids = layerIds ?? []
        return ids.isEmpty ? [Layer.mineId] : ids
    }
}
