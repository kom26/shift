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

    var isEmpty: Bool { events.isEmpty && workplaces.isEmpty && favorites.isEmpty }
}
