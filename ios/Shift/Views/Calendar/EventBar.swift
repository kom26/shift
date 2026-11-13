import SwiftUI

struct EventBar: View {
    @Environment(\.calendarBackground) private var calBg
    let span: BarSpan
    let height: CGFloat
    /// 時間の文字サイズ
    var fontSize: CGFloat = 10
    /// タイトルの文字サイズ。nil のときは、時間と同じ
    var titleSize: CGFloat?
    @AppStorage(BarFontChoice.key) private var barFont = BarFontChoice.zen.rawValue

    var body: some View {
        let _ = barFont
        if let m = span.event.taskMarker {
            if m.isLink {
                TaskLinkBar(taskId: m.taskId, title: span.event.title, color: span.event.color, span: span.span,
                            showsStart: span.isStart, showsDue: span.isEnd, height: height, fontSize: titleSize ?? fontSize)
            } else {
                TaskTagBar(title: span.event.title, color: span.event.color, isStart: m.isStart, height: height, fontSize: titleSize ?? fontSize)
            }
        } else {
            bar
        }
    }

    @ViewBuilder
    private var bar: some View {
        let ev = span.event
        let r: CGFloat = 4
        let lead: CGFloat = span.isStart ? 5 : 3
        // 文字は overlay に置く。バーの大きさは文字に左右されず、長いときは左詰めで「…」になる
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    let avail = max(0, geo.size.width - lead - 3)
                    label(ev, avail: avail)
                        .frame(width: avail, height: geo.size.height, alignment: .leading)
                        .padding(.leading, lead)
                }
            }
            .clipped()
            .foregroundStyle(EventColor.text(ev.color))
            .background(
                EventColor.fill(ev.color),
                in: UnevenRoundedRectangle(
                    topLeadingRadius: span.isStart ? r : 0,
                    bottomLeadingRadius: span.isStart ? r : 0,
                    bottomTrailingRadius: span.isEnd ? r : 0,
                    topTrailingRadius: span.isEnd ? r : 0))
            // 半透明の色の下地は、カレンダー背景ではなく、いつも標準の背景(背景を変えても、バーの色が変わらないように)
            .background(
                EventColor.base,
                in: UnevenRoundedRectangle(
                    topLeadingRadius: span.isStart ? r : 0,
                    bottomLeadingRadius: span.isStart ? r : 0,
                    bottomTrailingRadius: span.isEnd ? r : 0,
                    topTrailingRadius: span.isEnd ? r : 0))
    }
}

extension EventBar {
    /// 時間は数字の幅をそろえて「00:00-00:00」と同じ横幅にする
    @ViewBuilder
    fileprivate func label(_ ev: ShiftEvent, avail: CGFloat) -> some View {
        if !span.isStart {
            Text("…").font(.bar(titleSize ?? fontSize, weight: .bold)).lineLimit(1)
        } else if ev.barShowsTime {
            FixedWidthTimeText(text: Rules.timeLabel(ev), size: fontSize, maxWidth: avail)
        } else {
            Text(ev.title).font(.bar(titleSize ?? fontSize, weight: .bold)).lineLimit(1).truncationMode(.tail)
        }
    }
}

/// 長押しプレビュー用: 省略なしの全文ラベル (必要な幅ちょうど)
struct EventBarPreview: View {
    @Environment(\.calendarBackground) private var calBg
    let event: ShiftEvent
    let height: CGFloat
    var fontSize: CGFloat = 10
    var titleSize: CGFloat?
    /// 元のバーの幅。文字がこれより長いときだけ文字幅まで伸ばす
    var minWidth: CGFloat = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        Group {
            if event.barShowsTime {
                FixedWidthTimeText(text: Rules.timeLabel(event), size: fontSize)
            } else {
                Text(event.title).font(.bar(titleSize ?? fontSize, weight: .bold)).lineLimit(1).fixedSize()
            }
        }
            .padding(.horizontal, 8)
            .frame(minWidth: minWidth, alignment: .leading)
            .frame(height: height)
            .foregroundStyle(EventColor.text(event.color))
            .background(EventColor.fill(event.color), in: shape)
            .background(EventColor.base, in: shape)
            .clipShape(shape)
    }
}

private struct StampingKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// スタンプ中は予定バーを触れなくして、タップをその下の日付セルに通す
    var isStamping: Bool {
        get { self[StampingKey.self] }
        set { self[StampingKey.self] = newValue }
    }
}

private struct SharedViewKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// 共有カレンダーを表示している間は true(重複予定の赤表示などを出さない)
    var isSharedView: Bool {
        get { self[SharedViewKey.self] }
        set { self[SharedViewKey.self] = newValue }
    }
}

/// 月/週ビュー共用: SpanLayout の行を上から積んで描画する
struct SpanBars: View {
    @Environment(Store.self) private var store
    let rows: [[BarSpan]]
    let colW: CGFloat
    let barH: CGFloat
    var compactFont = false
    @Environment(\.isStamping) private var isStamping
    @AppStorage(BarFontSize.monthKey) private var monthDelta = 0.0
    @AppStorage(BarFontSize.weekKey) private var weekDelta = 0.0
    @AppStorage(BarFontSize.monthTitleKey) private var monthTitleDelta = 0.0
    @AppStorage(BarFontSize.weekTitleKey) private var weekTitleDelta = 0.0
    @AppStorage(BarFontChoice.key) private var barFont = BarFontChoice.zen.rawValue
    let leading: CGFloat
    var gap: CGFloat = 2
    /// バーをタップしたとき(タップした日の列の番号つき)。日付セルの選択と編集の振り分けは、呼ぶ側で行う
    let onTap: (ShiftEvent, Int) -> Void
    /// 長押しメニューの「編集」
    let onEdit: (ShiftEvent) -> Void

    /// 標準は、1日分の幅のバーに「00:00-00:00」が収まる大きさ。そこからユーザーが増減する
    private var fontSize: CGFloat {
        let base = FixedWidthTime.fitSize(width: colW - 2 - BarFontSize.sidePadding)
        return max(5, base + CGFloat(compactFont ? monthDelta : weekDelta))
    }

    /// タイトルの文字サイズ(時間とは別に、設定で変えられる)
    private var titleSize: CGFloat {
        let base = FixedWidthTime.fitSize(width: colW - 2 - BarFontSize.sidePadding)
        return max(5, base + CGFloat(compactFont ? monthTitleDelta : weekTitleDelta))
    }

    var body: some View {
        let _ = barFont
        ZStack(alignment: .topLeading) {
            ForEach(rows.indices, id: \.self) { r in
                ForEach(rows[r]) { s in
                    EventBar(span: s, height: barH, fontSize: fontSize, titleSize: titleSize)
                        .frame(width: max(0, colW * CGFloat(s.span) - 2), height: barH)
                        .gesture(SpatialTapGesture().onEnded { v in
                            let inBar = colW > 0 ? Int(v.location.x / colW) : 0
                            onTap(s.event, s.col + min(s.span - 1, max(0, inBar)))
                        })
                        // 長押しはドラッグ専用(メニューを付けると、長押しが取り合いになって動かせなくなる)
                        .eventDragSource(s.event, onOpen: onEdit)
                        .offset(x: leading + colW * CGFloat(s.col) + 1, y: CGFloat(r) * (barH + gap))
                }
            }
        }
        .frame(height: CGFloat(rows.count) * (barH + gap), alignment: .topLeading)
        .allowsHitTesting(!isStamping)
    }
}

/// 設定の「予定バーの文字サイズ」。標準からの増減(pt)を週・月で別々に持つ
enum BarFontSize {
    static let monthKey = "monthBarFontDelta"
    static let weekKey = "weekBarFontDelta"
    /// タイトルの文字サイズの増減(週・月)。上の monthKey・weekKey は、時間の文字サイズ
    static let monthTitleKey = "monthBarTitleDelta"
    static let weekTitleKey = "weekBarTitleDelta"
    static let range: ClosedRange<Double> = -2...3
    /// バーの左右の余白(先頭の 5 と末尾の 3)
    static let sidePadding: CGFloat = 8
    /// 月表示のバーの太さ(pt)。0 は標準(画面に合わせて自動)
    static let thicknessKey = "monthBarThickness"
    static let thicknessMax: CGFloat = 26
    /// 月表示で、入りきらない予定を、縦スクロールにするか(false は「+件数」)
    static let scrollKey = "monthBarOverflowScroll"

    /// 文字がはみ出さない、いちばん細いバーの太さ(文字が大きいほど、太くなる)。以前は文字+5pt だったが、細くできるよう、+2pt にした
    static func minBar(font: CGFloat) -> CGFloat { (font + 2).rounded(.up) }

    /// 文字サイズを、タイトルと時間で分ける前は、1 つの値だった。分けたあとは、その値を、両方の最初の値にする(一度だけ)
    static func migrate(defaults: UserDefaults = .standard) {
        for (legacy, title) in [(monthKey, monthTitleKey), (weekKey, weekTitleKey)] {
            guard defaults.object(forKey: title) == nil else { continue }
            defaults.set(defaults.double(forKey: legacy), forKey: title)
        }
    }
}
