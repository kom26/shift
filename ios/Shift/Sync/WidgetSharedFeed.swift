import Foundation

/// ウィジェットで共有カレンダーを見る設定のとき、その中身を取ってきてウィジェットに渡す
enum WidgetSharedFeed {
    @MainActor
    static func refresh(store: Store, calendars: [SharedCalendar], sharedView: SharedViewState) async {
        // 切り替えで見る共有カレンダーを、全部取ってくる
        let ids = Set(WidgetPrefs.load(WidgetPrefsKey.small).sharedCalendarIds
                      + WidgetPrefs.load(WidgetPrefsKey.medium).sharedCalendarIds)
        var fetched: [WidgetSharedCalendar] = []
        for id in ids {
            guard let cal = calendars.first(where: { $0.id == id && $0.status == .active }),
                  let snap = await sharedView.widgetSnapshot(of: cal) else { continue }
            fetched.append(snap)
        }
        WidgetSync.publish(store: store, shared: fetched)
    }
}
