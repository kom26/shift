import Foundation
import WidgetKit

/// 予定や設定が変わったら、ウィジェット用のデータを書き出して表示を更新する
enum WidgetSync {
    /// shared: 取ってきた共有カレンダーの中身。nil なら、前に書き出した分をそのまま使う
    static func publish(store: Store, shared: [WidgetSharedCalendar]? = nil) {
        let startMonday = UserDefaults.standard.bool(forKey: "startMonday")
        let small = WidgetPrefs.load(WidgetPrefsKey.small)
        let medium = WidgetPrefs.load(WidgetPrefsKey.medium)
        let wanted = Set([small.calendarId, medium.calendarId].compactMap { $0 })
        var kept = WidgetBridge.read()?.shared ?? []
        if let shared {
            let ids = Set(shared.map(\.id))
            kept = kept.filter { !ids.contains($0.id) } + shared
        }
        kept = kept.filter { wanted.contains($0.id) }
        WidgetBridge.write(WidgetData(snapshot: store.syncSnapshot(), startMonday: startMonday,
                                      small: small, medium: medium, shared: kept))
        WidgetCenter.shared.reloadAllTimelines()
    }
}
