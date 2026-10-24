import SwiftUI

struct EventBar: View {
    let span: BarSpan
    let height: CGFloat
    var fontSize: CGFloat = 10

    var body: some View {
        let ev = span.event
        let color = Color(hex: ev.color)
        let r: CGFloat = 4
        let label: String = !span.isStart
            ? "…"
            : ((ev.allDay || ev.startTime == nil) ? ev.title : Rules.timeLabel(ev))
        Text(label)
            .font(.system(size: fontSize, weight: .bold))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, span.isStart ? 5 : 3)
            .padding(.trailing, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .foregroundStyle(color)
            .background(
                color.opacity(0.16),
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
            .overlay(alignment: .leading) {
                if span.isStart {
                    Rectangle().fill(color).frame(width: 3)
                }
            }
    }
}

/// 月/週ビュー共用: SpanLayout の行を上から積んで描画する
struct SpanBars: View {
    @Environment(Store.self) private var store
    let rows: [[BarSpan]]
    let colW: CGFloat
    let barH: CGFloat
    let leading: CGFloat
    var gap: CGFloat = 2
    let onSelect: (ShiftEvent) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(rows.indices, id: \.self) { r in
                ForEach(rows[r]) { s in
                    EventBar(span: s, height: barH, fontSize: barH >= 16 ? 10 : 9)
                        .frame(width: max(0, colW * CGFloat(s.span) - 2), height: barH)
                        .onTapGesture { onSelect(s.event) }
                        .eventMenu(for: s.event, store: store, previewCornerRadius: 4, onEdit: onSelect)
                        .draggable(s.event.id)
                        .offset(x: leading + colW * CGFloat(s.col) + 1, y: CGFloat(r) * (barH + gap))
                }
            }
        }
        .frame(height: CGFloat(rows.count) * (barH + gap), alignment: .topLeading)
    }
}
