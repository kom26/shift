import SwiftUI

/// 横にあふれて自前でスクロールしている帯の枠(pager 座標)。ページ送りを無効にする領域
struct ScrollLockFramesKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

private struct StripContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct SummaryStrip: View {
    let label: String?
    let totals: [ColorTotal]
    let emptyText: String
    var fill: Color = .clear
    var labelColor: Color = .secondary
    var fontSize: CGFloat = 11

    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0

    private var overflowing: Bool { contentWidth > containerWidth + 0.5 && containerWidth > 0 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if let label {
                    Text(label).font(.app(fontSize - 1, weight: .semibold)).foregroundStyle(labelColor)
                }
                if totals.isEmpty {
                    Text(emptyText).font(.app(fontSize)).foregroundStyle(.secondary)
                } else {
                    ForEach(totals) { t in
                        HStack(spacing: 4) {
                            ColorDot(hex: t.color, size: 8)
                            Text(t.title).font(.app(fontSize)).lineLimit(1)
                            Text(Rules.formatHours(t.hours)).font(.app(fontSize, weight: .semibold))
                        }
                    }
                    if totals.count > 1 {
                        Text("合計 " + Rules.formatHours(totals.reduce(0) { $0 + $1.hours }))
                            .font(.app(fontSize, weight: .bold))
                    }
                }
            }
            .padding(.horizontal, 12)
            .fixedSize(horizontal: true, vertical: false)
            .background(GeometryReader { g in
                Color.clear.preference(key: StripContentWidthKey.self, value: g.size.width)
            })
        }
        .onPreferenceChange(StripContentWidthKey.self) { contentWidth = $0 }
        .background(GeometryReader { g in
            Color.clear
                .preference(key: ScrollLockFramesKey.self,
                            value: overflowing ? [g.frame(in: .named("pager"))] : [])
                .onAppear { containerWidth = g.size.width }
                .onChange(of: g.size.width) { _, new in containerWidth = new }
        })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(fill)
    }
}
