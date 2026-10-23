import SwiftUI

struct EventBar: View {
    let span: BarSpan
    let height: CGFloat

    var body: some View {
        let ev = span.event
        let r: CGFloat = 4
        Text(ev.allDay ? ev.title : (ev.startTime ?? ev.title))
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .foregroundStyle(.white)
            .background(
                Color(hex: ev.color),
                in: UnevenRoundedRectangle(
                    topLeadingRadius: span.isStart ? r : 0,
                    bottomLeadingRadius: span.isStart ? r : 0,
                    bottomTrailingRadius: span.isEnd ? r : 0,
                    topTrailingRadius: span.isEnd ? r : 0))
    }
}

/// 月/週ビュー共用: SpanLayout の行を上から積んで描画する
struct SpanBars: View {
    let rows: [[BarSpan]]
    let colW: CGFloat
    let barH: CGFloat
    let leading: CGFloat
    let onSelect: (ShiftEvent) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(rows.indices, id: \.self) { r in
                ForEach(rows[r]) { s in
                    EventBar(span: s, height: barH)
                        .frame(width: colW * CGFloat(s.span) - 2, height: barH)
                        .offset(x: leading + colW * CGFloat(s.col) + 1, y: CGFloat(r) * (barH + 2))
                        .onTapGesture { onSelect(s.event) }
                }
            }
        }
        .frame(height: CGFloat(rows.count) * (barH + 2), alignment: .topLeading)
    }
}
