import SwiftUI
import UniformTypeIdentifiers

struct MonthView: View {
    @Environment(Store.self) private var store
    @Environment(Holidays.self) private var holidays
    let anchor: String
    let startMonday: Bool
    let summaryOn: Bool
    let onSelectDay: (String) -> Void
    let onSelectEvent: (ShiftEvent) -> Void
    let onDropEvent: (String, String) -> Void
    let onSelectPayday: (String) -> Void

    @AppStorage("conflictWarningOn") private var conflictWarningOn = true
    @AppStorage("conflictGapMinutes") private var conflictGapMinutes = 0
    @State private var dropTarget: String?

    private let numH: CGFloat = 20
    private let barGap: CGFloat = 1
    private let bottomPad: CGFloat = 3
    private let stripH: CGFloat = 22

    var body: some View {
        let ym = Rules.ymd(anchor)
        let weeks = Rules.monthGrid(year: ym.year, month: ym.month, startMonday: startMonday)
        let monthBounds = Rules.monthBounds(of: anchor)
        let monthTotals = store.totals(from: monthBounds.first, to: monthBounds.last, isHoliday: { holidays.name(on: $0) != nil })
        let monthOrder = monthTotals.map(\.key)
        let conflictDays: Set<String> = conflictWarningOn ? Conflicts.days(events: store.events, minGapMinutes: conflictGapMinutes) : []
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
                // 区切り線 1pt ぶんを差し引いた、1週あたりの最小の高さ
                let weekRows = weeks.map { SpanLayout.rows(events: store.visibleEvents, weekCells: $0.map { Optional($0) }) }
                let n = CGFloat(max(1, weeks.count))
                let strip: CGFloat = summaryOn ? stripH : 0
                let minRow = (geo.size.height - n - 1) / n
                let barH = min(18, max(14, floor((minRow - stripH - numH - bottomPad) / 4) - 1))
                let needed = weekRows.map { numH + CGFloat($0.count) * (barH + barGap) + bottomPad + strip }
                let rowH = max(minRow, needed.max() ?? 0)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(weeks.indices, id: \.self) { i in
                            weekBlock(weeks[i], rows: weekRows[i], rowH: rowH, barH: barH, monthOrder: monthOrder, conflictDays: conflictDays)
                            Divider()
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            Divider()
            SummaryStrip(label: "月計", totals: monthTotals, emptyText: "データなし")
                .frame(height: stripH)
                .background(Color(.secondarySystemBackground))
        }
        .background {
            ZStack {
                Color(.systemBackground)
                MonthWatermark(number: ym.month)
            }
        }
    }

    private func weekBlock(_ cells: [String], rows: [[BarSpan]], rowH: CGFloat, barH: CGFloat, monthOrder: [String], conflictDays: Set<String>) -> some View {
        VStack(spacing: 0) {
            weekCells(cells, rows: rows, barH: barH, conflictDays: conflictDays)
                .frame(height: summaryOn ? rowH - stripH : rowH)
                .clipped()
            if summaryOn {
                SummaryStrip(label: "週計",
                             totals: store.totals(from: cells[0], to: cells[6], isHoliday: { holidays.name(on: $0) != nil }, orderBy: monthOrder),
                             emptyText: "-")
                    .frame(height: stripH)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground))
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color(.separator)).frame(height: 0.5)
                    }
            }
        }
    }

    private func weekCells(_ cells: [String], rows: [[BarSpan]], barH: CGFloat, conflictDays: Set<String>) -> some View {
        GeometryReader { geo in
            let w = geo.size.width / 7
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        dayCell(cells[i], conflict: conflictDays.contains(cells[i]))
                            .frame(width: w, height: geo.size.height)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(Color(.separator).opacity(0.5)).frame(width: 0.5)
                            }
                    }
                }
                SpanBars(rows: rows, colW: w, barH: barH, leading: 0, gap: barGap, onSelect: onSelectEvent)
                    .offset(y: numH)
            }
            .onDrop(of: [.plainText], delegate: EventDropDelegate(
                resolve: { p in
                    guard w > 0 else { return nil }
                    return cells[min(6, max(0, Int(p.x / w)))]
                },
                target: $dropTarget,
                onDrop: onDropEvent))
        }
    }

    private func dayCell(_ ds: String, conflict: Bool) -> some View {
        let inMonth = Rules.isSameMonth(ds, as: anchor)
        let holiday = holidays.name(on: ds)
        let type = Rules.dayType(ds, isHoliday: holiday != nil)
        let isToday = inMonth && ds == Rules.today()
        let isDrop = dropTarget == ds
        let bg: Color = isDrop ? Theme.accentSoft
            : conflict ? Color.red.opacity(0.16)
            : isToday ? Theme.accentSoft
            : (inMonth ? Color.clear : Color(.tertiarySystemFill))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("\(Rules.ymd(ds).day)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isToday ? Theme.accent : type.color)
                    .opacity(inMonth ? 1 : 0.45)
                Spacer(minLength: 0)
                if store.hasPayday(on: ds) {
                    PaydayCoinButton { onSelectPayday(ds) }
                }
            }
            .frame(height: numH)
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

/// 背面に敷く巨大な月数字 (薄く、タップを通す)
struct MonthWatermark: View {
    let number: Int
    var body: some View {
        Text("\(number)")
            .font(.system(size: 240, weight: .heavy))
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            .foregroundStyle(Color.primary.opacity(0.06))
            .allowsHitTesting(false)
    }
}

/// 給料日のコイン(2枚重ね)。タップで給料シートを開く
struct PaydayCoinButton: View {
    let action: () -> Void
    private let gold = Color(red: 0.95, green: 0.7, blue: 0.1)

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: "yensign.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(gold)
                Image(systemName: "yensign.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(gold)
                    .offset(x: 4, y: 2)
            }
            .frame(minWidth: 28, minHeight: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("給料日")
    }
}
