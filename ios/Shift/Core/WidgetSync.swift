import FirebaseAuth
import Foundation
import WidgetKit

/// 予定や設定が変わったら、ウィジェット用のデータを書き出して表示を更新する
enum WidgetSync {
    /// shared: 取ってきた共有カレンダーの中身。nil なら、前に書き出した分をそのまま使う
    static func publish(store: Store, shared: [WidgetSharedCalendar]? = nil) {
        let startMonday = UserDefaults.standard.bool(forKey: "startMonday")
        let small = WidgetPrefs.load(WidgetPrefsKey.small)
        let medium = WidgetPrefs.load(WidgetPrefsKey.medium)
        let wanted = Set(small.sharedCalendarIds + medium.sharedCalendarIds)
        var kept = WidgetBridge.read()?.shared ?? []
        if let shared {
            let ids = Set(shared.map(\.id))
            kept = kept.filter { !ids.contains($0.id) } + shared
        }
        kept = kept.filter { wanted.contains($0.id) }
        WidgetBridge.write(WidgetData(snapshot: store.syncSnapshot(), startMonday: startMonday,
                                      small: small, medium: medium, shared: kept, me: me()))
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 自分のプロフィール(名前とアイコン)。名前は、自分で付けたもの、なければ連携してきたもの、なければメールの手前(ProfileSettings.displayName と同じ順)
    private static func me() -> WidgetMe? {
        guard let user = Auth.auth().currentUser else { return nil }
        let defaults = UserDefaults.standard
        let custom = (defaults.string(forKey: "profile-name") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let provided = (user.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let emailName = user.email?.split(separator: "@").first.map(String.init) ?? ""
        let name = !custom.isEmpty ? custom : (!provided.isEmpty ? provided : emailName)
        return WidgetMe(uid: user.uid, name: name, avatar: defaults.string(forKey: "profile-avatar") ?? "")
    }
}
