import Foundation
import WidgetKit

/// 予定や設定が変わったら、ウィジェット用のデータを書き出して表示を更新する
enum WidgetSync {
    static func publish(store: Store) {
        let startMonday = UserDefaults.standard.bool(forKey: "startMonday")
        WidgetBridge.write(WidgetData(snapshot: store.syncSnapshot(), startMonday: startMonday))
        WidgetCenter.shared.reloadAllTimelines()
    }
}
