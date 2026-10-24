import CoreGraphics

/// 月表示とルート画面で共有する縦方向のレイアウト定数・計算
enum LayoutMath {
    static let numH: CGFloat = 16
    static let bottomPad: CGFloat = 2
    static let barGap: CGFloat = 1
    static let weekStripH: CGFloat = 18
    static let refBarH: CGFloat = 14
    static let weekdayHeaderH: CGFloat = 24
    static let monthStripH: CGFloat = 20
    static let unplacedHeaderH: CGFloat = 24
    static let minUnplacedBody: CGFloat = 92

    /// available = ヘッダーより下 (カレンダー + 未配置エリア) の高さ
    static func monthCalendarHeight(available: CGFloat, weeks: Int) -> CGFloat {
        let perWeek = numH + 4 * (refBarH + barGap) + bottomPad + weekStripH + 1
        let needed = weekdayHeaderH + CGFloat(weeks) * perWeek + monthStripH
        let cap = available - unplacedHeaderH - minUnplacedBody
        return min(needed, max(cap, 0))
    }
}
