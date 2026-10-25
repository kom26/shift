import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct MonthView: View {
    @Environment(Store.self) private var store
    @Environment(Holidays.self) private var holidays
    let anchor: String
    let startMonday: Bool
    let summaryOn: Bool
    let selectedDate: String?
    let onSelectDay: (String) -> Void
    let onSelectEvent: (ShiftEvent) -> Void
    let onDropEvent: (String, String) -> Void
    let onSelectPayday: (String) -> Void
    let onLongPressDay: (String) -> Void

    @AppStorage("conflictWarningOn") private var conflictWarningOn = true
    @AppStorage("conflictGapMinutes") private var conflictGapMinutes = 0
    @State private var dropTarget: String?

    private let numH = LayoutMath.numH
    private let barGap = LayoutMath.barGap
    private let bottomPad = LayoutMath.bottomPad
    private let stripH = LayoutMath.weekStripH
    private let monthStripH = LayoutMath.monthStripH

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
                        .font(.app(10, weight: .medium))
                        .foregroundStyle(dow == 0 ? Theme.sunday : dow == 6 ? Theme.saturday : Color.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: LayoutMath.weekdayHeaderH - 1)
            Divider()
            GeometryReader { geo in
                // 区切り線 1pt ぶんを差し引いた、1週あたりの最小の高さ
                let weekRows = weeks.map { SpanLayout.rows(events: store.visibleEvents, weekCells: $0.map { Optional($0) }) }
                let n = CGFloat(max(1, weeks.count))
                let strip: CGFloat = summaryOn ? stripH : 0
                let minRow = (geo.size.height - (n - 1)) / n
                let barH = min(16, max(11, floor((minRow - stripH - numH - bottomPad) / 4) - 1))
                let needed = weekRows.map { numH + CGFloat($0.count) * (barH + barGap) + bottomPad + strip }
                let rowH = max(minRow, needed.max() ?? 0)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(weeks.indices, id: \.self) { i in
                            weekBlock(weeks[i], rows: weekRows[i], rowH: rowH, barH: barH, monthOrder: monthOrder, conflictDays: conflictDays)
                            if i < weeks.count - 1 { Divider() }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            SummaryStrip(label: "月計", totals: monthTotals, emptyText: "データなし",
                         fill: Theme.accentSoft, labelColor: Color.secondary, fontSize: 10)
                .frame(height: monthStripH)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color(.separator)).frame(height: 0.5)
                }
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
                             emptyText: "-",
                             fill: Color(.systemBackground), labelColor: Color.secondary, fontSize: 9.5)
                    .frame(height: stripH)
                    .frame(maxWidth: .infinity)
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
                SpanBars(rows: rows, colW: w, barH: barH, compactFont: true, leading: 0, gap: barGap, onSelect: onSelectEvent)
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

    /// ドラッグ中の予定を ds に置くと、時間つきの他の予定と重なるか
    private func dropConflicts(_ ds: String) -> Bool {
        guard let id = DragState.shared.draggingId, let m = store.dropPreview(id: id, on: ds) else { return false }
        return DropCheck.overlaps(moved: m, others: store.events)
    }

    private func dayCell(_ ds: String, conflict: Bool) -> some View {
        let inMonth = Rules.isSameMonth(ds, as: anchor)
        let holiday = holidays.name(on: ds)
        let type = Rules.dayType(ds, isHoliday: holiday != nil)
        let isToday = inMonth && ds == Rules.today()
        let isDrop = dropTarget == ds
        let dropBad = isDrop && dropConflicts(ds)
        let bg: Color = isDrop ? (dropBad ? Color.red.opacity(0.18) : Theme.accentSoft)
            : conflict ? Color.red.opacity(0.16)
            : isToday ? Theme.accentSoft
            : (inMonth ? Color.clear : Color(.tertiarySystemFill))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("\(Rules.ymd(ds).day)")
                    .font(.app(10, weight: .medium))
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
            if selectedDate == ds {
                Rectangle().strokeBorder(Theme.accent, lineWidth: 1.5)
            }
        }
        .overlay {
            if isDrop {
                Rectangle()
                    .strokeBorder(dropBad ? Color.red : Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelectDay(ds) }
        .onLongPressGesture(minimumDuration: 0.45) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onLongPressDay(ds)
        }
    }
}

/// 背面に敷く巨大な月数字 (薄く、タップを通す)
struct MonthWatermark: View {
    let number: Int
    var body: some View {
        Text("\(number)")
            .font(.app(240, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            .foregroundStyle(Color.primary.opacity(0.06))
            .allowsHitTesting(false)
    }
}

/// 給料日のコイン(積み重ねアイコン)。タップで給料シートを開く
struct PaydayCoinButton: View {
    let action: () -> Void
    private let gold = Color(red: 0.95, green: 0.7, blue: 0.1)

    var body: some View {
        Image("CoinStack")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 12, height: 12)
                .foregroundStyle(gold)
                .padding(2)
            .frame(minWidth: 28, minHeight: 24)
            .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("給料日")
    }
}
