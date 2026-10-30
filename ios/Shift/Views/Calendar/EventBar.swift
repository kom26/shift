import SwiftUI

struct EventBar: View {
    let span: BarSpan
    let height: CGFloat
    var fontSize: CGFloat = 10

    var body: some View {
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
            .background(
                Color(.systemBackground),
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
            Text("…").font(.bar(fontSize, weight: .bold)).lineLimit(1)
        } else if ev.barShowsTime {
            FixedWidthTimeText(text: Rules.timeLabel(ev), size: fontSize, maxWidth: avail)
        } else {
            Text(ev.title).font(.bar(fontSize, weight: .bold)).lineLimit(1).truncationMode(.tail)
        }
    }
}

/// 長押しプレビュー用: 省略なしの全文ラベル (必要な幅ちょうど)
struct EventBarPreview: View {
    let event: ShiftEvent
    let height: CGFloat
    var fontSize: CGFloat = 10
    /// 元のバーの幅。文字がこれより長いときだけ文字幅まで伸ばす
    var minWidth: CGFloat = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        Group {
            if event.barShowsTime {
                FixedWidthTimeText(text: Rules.timeLabel(event), size: fontSize)
            } else {
                Text(event.title).font(.bar(fontSize, weight: .bold)).lineLimit(1).fixedSize()
            }
        }
            .padding(.horizontal, 8)
            .frame(minWidth: minWidth, alignment: .leading)
            .frame(height: height)
            .foregroundStyle(EventColor.text(event.color))
            .background(EventColor.fill(event.color), in: shape)
            .background(Color(.systemBackground), in: shape)
            .clipShape(shape)
    }
}

/// 月/週ビュー共用: SpanLayout の行を上から積んで描画する
struct SpanBars: View {
    @Environment(Store.self) private var store
    let rows: [[BarSpan]]
    let colW: CGFloat
    let barH: CGFloat
    var compactFont = false
    @AppStorage(BarFontSize.monthKey) private var monthDelta = 0.0
    @AppStorage(BarFontSize.weekKey) private var weekDelta = 0.0
    let leading: CGFloat
    var gap: CGFloat = 2
    let onSelect: (ShiftEvent) -> Void

    /// 標準は、1日分の幅のバーに「00:00-00:00」が収まる大きさ。そこからユーザーが増減する
    private var fontSize: CGFloat {
        let base = FixedWidthTime.fitSize(width: colW - 2 - BarFontSize.sidePadding)
        return max(5, base + CGFloat(compactFont ? monthDelta : weekDelta))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(rows.indices, id: \.self) { r in
                ForEach(rows[r]) { s in
                    EventBar(span: s, height: barH, fontSize: fontSize)
                        .frame(width: max(0, colW * CGFloat(s.span) - 2), height: barH)
                        .onTapGesture { onSelect(s.event) }
                        .eventMenu(for: s.event, store: store, onEdit: onSelect) {
                            EventBarPreview(event: s.event, height: barH, fontSize: fontSize, minWidth: max(0, colW * CGFloat(s.span) - 2))
                        }
                        .draggable(DragState.shared.begin(s.event.id))
                        .opacity(DragState.shared.isDragging && DragState.shared.draggingId == s.event.id ? 0.35 : 1)
                        .offset(x: leading + colW * CGFloat(s.col) + 1, y: CGFloat(r) * (barH + gap))
                }
            }
        }
        .frame(height: CGFloat(rows.count) * (barH + gap), alignment: .topLeading)
    }
}

/// 設定の「予定バーの文字サイズ」。標準からの増減(pt)を週・月で別々に持つ
enum BarFontSize {
    static let monthKey = "monthBarFontDelta"
    static let weekKey = "weekBarFontDelta"
    static let range: ClosedRange<Double> = -2...3
    /// バーの左右の余白(先頭の 5 と末尾の 3)
    static let sidePadding: CGFloat = 8
}
