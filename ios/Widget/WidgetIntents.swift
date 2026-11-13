import AppIntents
import WidgetKit

/// 小: 前の日・次の日。アプリは開かず、ウィジェットの表示だけ切り替える
struct StepDayIntent: AppIntent {
    static var title: LocalizedStringResource = "日を移動"
    static var isDiscoverable: Bool { false }

    @Parameter(title: "日数") var delta: Int

    init() { delta = 0 }
    init(delta: Int) { self.delta = delta }

    func perform() async throws -> some IntentResult {
        WidgetOffset(key: "day").step(delta)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetBridge.kind)
        return .result()
    }
}

struct ResetDayIntent: AppIntent {
    static var title: LocalizedStringResource = "今日へ戻る"
    static var isDiscoverable: Bool { false }

    func perform() async throws -> some IntentResult {
        WidgetOffset(key: "day").set(0)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetBridge.kind)
        return .result()
    }
}

/// 右上のボタン: アプリの設定で選んだカレンダーを、順に切り替える(小と中で別々)
struct CycleCalendarIntent: AppIntent {
    static var title: LocalizedStringResource = "カレンダーを切り替え"
    static var isDiscoverable: Bool { false }

    /// "small" / "medium"
    @Parameter(title: "大きさ") var size: String

    init() { size = "small" }
    init(size: String) { self.size = size }

    func perform() async throws -> some IntentResult {
        let data = WidgetBridge.read()
        let prefs = (size == "medium" ? data?.medium : data?.small) ?? WidgetPrefs()
        WidgetCalendarCursor(size: size).advance(count: prefs.calendarIds.count)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetBridge.kind)
        return .result()
    }
}

/// 中: 前の週・次の週
struct StepWeekIntent: AppIntent {
    static var title: LocalizedStringResource = "週を移動"
    static var isDiscoverable: Bool { false }

    @Parameter(title: "週数") var delta: Int

    init() { delta = 0 }
    init(delta: Int) { self.delta = delta }

    func perform() async throws -> some IntentResult {
        WidgetOffset(key: "week").step(delta)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetBridge.kind)
        return .result()
    }
}

struct ResetWeekIntent: AppIntent {
    static var title: LocalizedStringResource = "今週へ戻る"
    static var isDiscoverable: Bool { false }

    func perform() async throws -> some IntentResult {
        WidgetOffset(key: "week").set(0)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetBridge.kind)
        return .result()
    }
}
