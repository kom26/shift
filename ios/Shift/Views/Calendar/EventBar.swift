import SwiftUI

struct EventBar: View {
    let span: BarSpan
    let height: CGFloat
    var fontSize: CGFloat = 10

    var body: some View {
        let ev = span.event
        let r: CGFloat = 4
        let label: String = !span.isStart
            ? "…"
            : ((ev.allDay || ev.startTime == nil) ? ev.title : Rules.timeLabel(ev))
        Text(label)
            .font(.app(fontSize, weight: .bold))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, span.isStart ? 5 : 3)
            .padding(.trailing, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
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

/// 長押しプレビュー用: 省略なしの全文ラベル (必要な幅ちょうど)
struct EventBarPreview: View {
    let event: ShiftEvent
    let height: CGFloat
    var fontSize: CGFloat = 10

    var body: some View {
        let label = (event.allDay || event.startTime == nil) ? event.title : Rules.timeLabel(event)
        let shape = RoundedRectangle(cornerRadius: 4)
        Text(label)
            .font(.app(fontSize, weight: .bold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
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
    let leading: CGFloat
    var gap: CGFloat = 2
    let onSelect: (ShiftEvent) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(rows.indices, id: \.self) { r in
                ForEach(rows[r]) { s in
                    EventBar(span: s, height: barH, fontSize: compactFont ? (barH >= 14 ? 9 : 8) : (barH >= 16 ? 10 : 9))
                        .frame(width: max(0, colW * CGFloat(s.span) - 2), height: barH)
                        .onTapGesture { onSelect(s.event) }
                        .eventMenu(for: s.event, store: store, onEdit: onSelect) {
                            EventBarPreview(event: s.event, height: barH, fontSize: compactFont ? (barH >= 14 ? 9 : 8) : (barH >= 16 ? 10 : 9))
                        }
                        .draggable(s.event.id)
                        .offset(x: leading + colW * CGFloat(s.col) + 1, y: CGFloat(r) * (barH + gap))
                }
            }
        }
        .frame(height: CGFloat(rows.count) * (barH + gap), alignment: .topLeading)
    }
}
