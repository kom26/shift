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
    @State private var annivTarget: AnnivTarget?
    @Environment(\.isStamping) private var isStamping

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
        // 記念日・誕生日のアイコンは、週計を出すときは競合するので出さない
        let annivMap: [String: [Anniversary]] = summaryOn ? [:] : Dictionary(
            weeks.flatMap { $0 }.map { ($0, store.anniversaries(on: $0)) }.filter { !$0.1.isEmpty },
            uniquingKeysWith: { a, _ in a })
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
                // 予定3本+週計行が入る高さを基準にバーを太くする(増えたら縦スクロール)
                let barH = min(20, max(11, floor((minRow - stripH - numH - bottomPad) / 3) - 1))
                let needed = weeks.indices.map { neededHeight(cells: weeks[$0], rows: weekRows[$0], barH: barH, strip: strip, annivMap: annivMap) }
                // 予定が多い週が増やした高さは、予定が少ない週から削って吸収する(最低3本ぶんは残す)
                let floor3 = numH + 3 * (barH + barGap) + bottomPad + strip
                let extra = needed.reduce(0) { $0 + max(0, $1 - minRow) }
                let room = needed.map { $0 <= minRow ? minRow - max($0, floor3) : 0 }.map { max(0, $0) }
                let roomTotal = room.reduce(0, +)
                let taken = roomTotal > 0 ? min(extra, roomTotal) : 0
                let heights: [CGFloat] = needed.indices.map { i in
                    needed[i] > minRow ? needed[i] : minRow - (roomTotal > 0 ? taken * room[i] / roomTotal : 0)
                }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(weeks.indices, id: \.self) { i in
                            weekBlock(weeks[i], rows: weekRows[i], rowH: heights[i], barH: barH, monthOrder: monthOrder, conflictDays: conflictDays, annivMap: annivMap)
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
        .sheet(item: $annivTarget) { AnniversaryDetailSheet(id: $0.id, asOf: $0.date) }
    }

    private func weekBlock(_ cells: [String], rows: [[BarSpan]], rowH: CGFloat, barH: CGFloat, monthOrder: [String], conflictDays: Set<String>, annivMap: [String: [Anniversary]]) -> some View {
        VStack(spacing: 0) {
            weekCells(cells, rows: rows, barH: barH, conflictDays: conflictDays, annivMap: annivMap)
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

    private func weekCells(_ cells: [String], rows: [[BarSpan]], barH: CGFloat, conflictDays: Set<String>, annivMap: [String: [Anniversary]]) -> some View {
        GeometryReader { geo in
            let w = geo.size.width / 7
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        dayCell(cells[i], conflict: conflictDays.contains(cells[i]), annivs: annivMap[cells[i]] ?? [], iconSize: barH)
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

    /// 1週ぶんに必要な高さ。記念日のアイコンがある日は、その日のバーの下にもう1本ぶん確保する
    private func neededHeight(cells: [String], rows: [[BarSpan]], barH: CGFloat, strip: CGFloat,
                              annivMap: [String: [Anniversary]]) -> CGFloat {
        let lane = barH + barGap
        var lanes = rows.count
        for col in 0..<7 where annivMap[cells[col]] != nil {
            let used = rows.indices.filter { r in rows[r].contains { $0.col <= col && col < $0.col + $0.span } }
                .map { $0 + 1 }.max() ?? 0
            lanes = max(lanes, used + 1)
        }
        return numH + CGFloat(lanes) * lane + bottomPad + strip
    }

    /// ドラッグ中の予定を ds に置くと、時間つきの他の予定と重なるか
    private func dropConflicts(_ ds: String) -> Bool {
        guard let id = DragState.shared.draggingId, let m = store.dropPreview(id: id, on: ds) else { return false }
        return DropCheck.overlaps(moved: m, others: store.events)
    }

    private func dayCell(_ ds: String, conflict: Bool, annivs: [Anniversary], iconSize: CGFloat) -> some View {
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
                if store.hasAlarm(on: ds) {
                    Image(systemName: "bell.fill")
                        .font(.app(9))
                        .foregroundStyle(Theme.alarm)
                        .padding(.trailing, store.hasPayday(on: ds) ? 2 : 3)
                        .accessibilityLabel("アラーム")
                }
                // 給料日のコインはセルの右上の角に付ける(アラームはその左)
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
        .overlay(alignment: .bottomTrailing) {
            // 予定のバーの下(右下)に右詰めで並べる。足りない分は週の高さを広げて確保している
            HStack(spacing: 1) {
                ForEach(annivs.prefix(3)) { a in
                    AnniversaryIcon(icon: a.icon, color: a.color, size: iconSize)
                        .onTapGesture { annivTarget = AnnivTarget(id: a.id, date: ds) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(a.name)
                }
            }
            .padding(.trailing, 2)
            .padding(.bottom, 1)
            .allowsHitTesting(!isStamping)
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelectDay(ds) }
        .onLongPressGesture(minimumDuration: 0.45) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onLongPressDay(ds)
        }
    }
}

struct AnnivTarget: Identifiable {
    let id: String
    let date: String
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
    /// スタンプ中は押せない(タップはその下の日付セルに通す)
    @Environment(\.isStamping) private var isStamping
    private let gold = Color(red: 0.95, green: 0.7, blue: 0.1)

    var body: some View {
        Image("CoinStack")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 12, height: 12)
                .foregroundStyle(gold)
            .frame(width: 16, height: 16, alignment: .topTrailing)
            // セルの枠線(0.5〜1pt)に被らないよう、角から 1.5pt だけ内側に置く
            .padding(.top, 1.5)
            .padding(.trailing, 1.5)
            .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .allowsHitTesting(!isStamping)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("給料日")
    }
}
