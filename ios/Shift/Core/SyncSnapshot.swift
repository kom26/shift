import Foundation

/// 端末間で同期するデータ一式
struct SyncSnapshot: Codable, Equatable {
    var events: [ShiftEvent]
    var workplaces: [Workplace]
    var favorites: [ShiftEvent]
    var customColors: [String]
    var hiddenSuggestions: [String]
    /// セット済みのアラームの記録。新しい端末では AlarmKit 側に実体がないので、許可を取り直して入れ直す
    var alarms: [AlarmEntry]?
    /// 記念日・誕生日。古いデータには無いので省略可
    var anniversaries: [Anniversary]?
    /// 通常予定のラベル。古いデータには無いので省略可
    var labels: [EventLabel]?
    /// 以前のレイヤー。読むだけで、書き出さない(ラベルに引き継ぐ)
    var layers: [EventLabel]?
    /// 端末の設定(表示・給料・スヌーズ・名前とアバター・ウィジェットなど)。古いデータには無いので省略可
    var prefs: [String: String]?

    var isEmpty: Bool { events.isEmpty && workplaces.isEmpty && favorites.isEmpty }
}
