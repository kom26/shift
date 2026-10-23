import SwiftUI
import UniformTypeIdentifiers

struct MonthView: View {
    @Environment(Store.self) private var store
    @Environment(Holidays.self) private var holidays
    let anchor: String
    let startMonday: Bool
    let summaryMode: Int   // 0 なし / 1 週計 / 2 月計
    let onSelectDay: (String) -> Void
    let onSelectEvent: (ShiftEvent) -> Void
    let onDropEvent: (String, String) -> Void

    @State private var dropTarget: String?

    private let numH: CGFloat = 22
    private let barH: CGFloat = 20
    private let barGap: CGFloat = 2
    private let bottomPad: CGFloat = 6
    private let stripH: CGFloat = 24

    var body: some View {
        let ym = Rules.ymd(anchor)
        let weeks = Rules.monthGrid(year: ym.year, month: ym.month, startMonday: startMonday)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(Rules.weekdayLabels(startMonday: startMonday).enumerated()), id: \.offset) { i, label in
                    let dow = startMonday ? (i + 1) % 7 : i
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(dow == 0 ? Theme.sunday : dow == 6 ? Theme.saturday : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
            }
            Divider()
            GeometryReader { geo in
                let minRow = geo.size.height / CGFloat(max(1, weeks.count))
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(weeks.indices, id: \.self) { i in
                            weekRow(weeks[i], minRow: minRow)
                            Divider()
                        }
                    }
                }
            }
            if summaryMode == 2 {
                let b = Rules.monthBounds(of: anchor)
                Divider()
                SummaryStrip(label: "月計", totals: store.totals(from: b.first, to: b.last), emptyText: "データなし")
            }
        }
    }

    private func weekRow(_ cells: [String], minRow: CGFloat) -> some View {
        let rows = SpanLayout.rows(events: store.visibleEvents, weekCells: cells.map { Optional($0) })
        let barsH = CGFloat(rows.count) * (barH + barGap)
        let rowH = max(minRow, numH + barsH + bottomPad + (summaryMode == 1 ? stripH : 0))
        return GeometryReader { geo in
            let w = geo.size.width / 7
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        dayCell(cells[i])
                            .frame(width: w, height: geo.size.height)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(Color(.separator).opacity(0.5)).frame(width: 0.5)
                            }
                    }
                }
                SpanBars(rows: rows, colW: w, barH: barH, leading: 0, onSelect: onSelectEvent)
                    .offset(y: numH)
                if summaryMode == 1 {
                    VStack {
                        Spacer(minLength: 0)
                        SummaryStrip(label: nil,
                                     totals: store.totals(from: cells[0], to: cells[6]),
                                     emptyText: "-")
                            .frame(height: stripH)
                    }
                }
            }
            .onDrop(of: [.plainText], delegate: EventDropDelegate(
                resolve: { p in
                    guard w > 0 else { return nil }
                    return cells[min(6, max(0, Int(p.x / w)))]
                },
                target: $dropTarget,
                onDrop: onDropEvent))
        }
        .frame(height: rowH)
        .clipped()
    }

    private func dayCell(_ ds: String) -> some View {
        let inMonth = Rules.isSameMonth(ds, as: anchor)
        let holiday = holidays.name(on: ds)
        let type = Rules.dayType(ds, isHoliday: holiday != nil)
        let isToday = inMonth && ds == Rules.today()
        let isDrop = dropTarget == ds
        let bg: Color = isDrop || isToday ? Theme.accentSoft : (inMonth ? Color.clear : Color(.tertiarySystemFill))
        return VStack(alignment: .leading, spacing: 0) {
            Text("\(Rules.ymd(ds).day)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isToday ? Theme.accent : type.color)
                .opacity(inMonth ? 1 : 0.45)
                .frame(height: numH, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg)
        .overlay {
            if isDrop {
                Rectangle()
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelectDay(ds) }
    }
}
