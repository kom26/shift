import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct MonthView: View {
    /// 位置を覚えるときのキー。隣の月のページにも同じ週が出るので、月ごとに分ける
    private var dropKeyPrefix: String { "week-" + String(anchor.prefix(7)) + "-" }
    @Environment(Store.self) private var store
    @Environment(\.calendarBackground) private var calBg
    @Environment(Holidays.self) private var holidays
    let anchor: String
    let startMonday: Bool
    let summaryOn: Bool
    let selectedDate: String?
    let onSelectDay: (String) -> Void
    let onSelectEvent: (ShiftEvent) -> Void
    /// 予定バーのタップ(タップした日つき)
    let onTapEvent: (ShiftEvent, String) -> Void
    let onDropEvent: (String, String) -> Void
    let onSelectPayday: (String) -> Void
    let onLongPressDay: (String) -> Void

    @AppStorage("conflictWarningOn") private var conflictWarningOn = true
    @Environment(\.isSharedView) private var isSharedView
    @AppStorage("conflictGapMinutes") private var conflictGapMinutes = 0
    @AppStorage(BarFontSize.monthKey) private var monthDelta = 0.0
    /// 開始と締切を点線でつなぐか(設定。はじめはオフ)
    @AppStorage("taskLinkDots") private var taskLinkDots = false
    @AppStorage(BarFontSize.monthTitleKey) private var monthTitleDelta = 0.0
    @AppStorage(BarFontChoice.key) private var barFont = BarFontChoice.zen.rawValue
    @AppStorage(BarFontSize.thicknessKey) private var thickness = 0.0
    @AppStorage(BarFontSize.scrollKey) private var scrollOnOverflow = false
    @State private var dropTarget: String?
    @State private var annivTarget: AnnivTarget?
    @Environment(\.isStamping) private var isStamping

    private let numH = LayoutMath.numH
    private let barGap = LayoutMath.barGap
    private let bottomPad = LayoutMath.bottomPad
    private let stripH = LayoutMath.weekStripH
    private let monthStripH = LayoutMath.monthStripH

    var body: some View {
        let _ = barFont
        let ym = Rules.ymd(anchor)
        let weeks = Rules.monthGrid(year: ym.year, month: ym.month, startMonday: startMonday)
        let monthBounds = Rules.monthBounds(of: anchor)
        let monthTotals = store.totals(from: monthBounds.first, to: monthBounds.last, isHoliday: { holidays.name(on: $0) != nil })
        let monthOrder = monthTotals.map(\.key)
        // 記念日・誕生日のアイコンは、週計を出すときは競合するので出さない
        let annivMap: [String: [Anniversary]] = summaryOn ? [:] : Dictionary(
            weeks.flatMap { $0 }.map { ($0, store.anniversaries(on: $0)) }.filter { !$0.1.isEmpty },
            uniquingKeysWith: { a, _ in a })
        let conflictDays: Set<String> = conflictWarningOn && !isSharedView ? Conflicts.days(events: store.events, minGapMinutes: conflictGapMinutes) : []
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
                // 開始・締切の印も、予定と同じ決まりで行に詰める
                let calEvents = store.visibleEvents + store.taskMarkers(linked: taskLinkDots)
                let fullRows = weeks.map { SpanLayout.rows(events: calEvents, weekCells: $0.map { Optional($0) }) }
                let lay = monthLayout(weeks: weeks, fullRows: fullRows, size: geo.size, annivMap: annivMap)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(weeks.indices, id: \.self) { i in
                            weekBlock(weeks[i], rows: lay.rows[i], hidden: lay.hidden[i], rowH: lay.heights[i], barH: lay.barH, monthOrder: monthOrder, conflictDays: conflictDays, annivMap: annivMap)
                            if i < weeks.count - 1 { Divider() }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            // 共有カレンダーには、月計も週計も出さない
            if !isSharedView {
                SummaryStrip(label: "月計", totals: monthTotals, emptyText: "データなし",
                             fill: Theme.accentSoft, labelColor: Color.secondary, fontSize: 10)
                    .frame(height: monthStripH)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color(.separator)).frame(height: 0.5)
                    }
            }
        }
        .background {
            ZStack {
                calBg
                MonthWatermark(number: ym.month)
            }
        }
        .sheet(item: $annivTarget) { AnniversaryDetailSheet(id: $0.id, asOf: $0.date) }
    }

    private func weekBlock(_ cells: [String], rows: [[BarSpan]], hidden: [Int], rowH: CGFloat, barH: CGFloat, monthOrder: [String], conflictDays: Set<String>, annivMap: [String: [Anniversary]]) -> some View {
        VStack(spacing: 0) {
            weekCells(cells, rows: rows, hidden: hidden, barH: barH, conflictDays: conflictDays, annivMap: annivMap)
                .frame(height: summaryOn ? rowH - stripH : rowH)
                .clipped()
            if summaryOn {
                SummaryStrip(label: "週計",
                             totals: store.totals(from: cells[0], to: cells[6], isHoliday: { holidays.name(on: $0) != nil }, orderBy: monthOrder),
                             emptyText: "-",
                             fill: calBg, labelColor: Color.secondary, fontSize: 9.5)
                    .frame(height: stripH)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color(.separator)).frame(height: 0.5)
                    }
            }
        }
    }

    private func weekCells(_ cells: [String], rows: [[BarSpan]], hidden: [Int], barH: CGFloat, conflictDays: Set<String>, annivMap: [String: [Anniversary]]) -> some View {
        GeometryReader { geo in
            let w = geo.size.width / 7
            let rowH = geo.size.height
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        dayCell(cells[i], conflict: conflictDays.contains(cells[i]), annivs: annivMap[cells[i]] ?? [], cellW: w)
                            .frame(width: w, height: geo.size.height)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(Color(.separator).opacity(0.5)).frame(width: 0.5)
                            }
                    }
                }
                SpanBars(rows: rows, colW: w, barH: barH, compactFont: true, leading: 0, gap: barGap,
                         onTap: { ev, col in onTapEvent(ev, cells[min(6, max(0, col))]) }, onEdit: onSelectEvent)
                    .offset(y: numH)
                // 入りきらなかった予定の数(「+件数」)
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        ZStack(alignment: .bottomLeading) {
                            Color.clear
                            if i < hidden.count, hidden[i] > 0 {
                                Text("+\(hidden[i])")
                                    .font(.app(9, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 4)
                                    .padding(.bottom, 1)
                            }
                        }
                        .frame(width: w, height: geo.size.height)
                    }
                }
                .allowsHitTesting(false)
                movePreview(cells: cells, rows: rows, colW: w, barH: barH)
            }
            .onDrop(of: [.plainText], delegate: EventDropDelegate(
                resolve: { p in
                    guard w > 0 else { return nil }
                    return cells[min(6, max(0, Int(p.x / w)))]
                },
                target: $dropTarget,
                originKey: dropKeyPrefix + cells[0],
                cellRect: { p in
                    guard w > 0 else { return .zero }
                    return CGRect(x: CGFloat(min(6, max(0, Int(p.x / w)))) * w, y: 0, width: w, height: rowH)
                },
                onDrop: onDropEvent))
            .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: {
                DragState.shared.dropOrigins[dropKeyPrefix + cells[0]] = $0
            }
        }
    }

    /// 移動/コピーの選択中、移動先の日の、いま見えている予定の下に、移動後の予定を点線の縁取りのバーで出す
    @ViewBuilder
    private func movePreview(cells: [String], rows: [[BarSpan]], colW: CGFloat, barH: CGFloat) -> some View {
        if let id = DragState.shared.pendingId, let date = DragState.shared.pendingDate,
           let col = cells.firstIndex(of: date), let m = store.dropPreview(id: id, on: date) {
            let used = rows.indices.filter { r in rows[r].contains { $0.col <= col && col < $0.col + $0.span } }
                .map { $0 + 1 }.max() ?? 0
            let hex = m.color
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: hex).opacity(0.22))
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color(hex: hex), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                .overlay(Text(m.barShowsTime ? Rules.timeLabel(m) : m.title)
                    .font(.bar(9, weight: .bold)).lineLimit(1)
                    .foregroundStyle(EventColor.text(hex)).padding(.horizontal, 3), alignment: .leading)
                .frame(width: max(8, colW - 2), height: barH)
                .offset(x: CGFloat(col) * colW + 1, y: numH + CGFloat(used) * (barH + barGap))
                .allowsHitTesting(false)
        }
    }

    private struct MonthLayout {
        let barH: CGFloat
        /// 週ごとに、表示するバーの行
        let rows: [[[BarSpan]]]
        /// 週ごとの、日ごとの「入りきらない」件数
        let hidden: [[Int]]
        let heights: [CGFloat]
    }

    /// 月の週ごとの高さとバー。予定の少ない週は必要なぶんだけにして、浮いた高さを多い週に回す。
    /// それでも収まらないとき、「+件数」なら、出す本数を全部の週でそろえて減らす。「縦にスクロール」なら、全部出す
    private func monthLayout(weeks: [[String]], fullRows: [[[BarSpan]]], size: CGSize,
                             annivMap: [String: [Anniversary]]) -> MonthLayout {
        let n = CGFloat(max(1, weeks.count))
        let strip: CGFloat = summaryOn ? stripH : 0
        // 週の間の区切り線(Divider)の太さは 1pt ではなく 1px ぶん
        let divH = 1 / UIScreen.main.scale
        let avail = size.height - (n - 1) * divH
        let colW = size.width / 7
        // バーの太さ: 設定があればそれ。なければ、予定3本ぶんが入る太さ。どちらも、文字が入る太さより細くはしない
        let baseFit = FixedWidthTime.fitSize(width: colW - 2 - BarFontSize.sidePadding)
        let fontPx = max(5, baseFit + CGFloat(max(monthDelta, monthTitleDelta)))
        let minBar = BarFontSize.minBar(font: fontPx)
        let minRow = avail / n
        let autoBar = min(20, max(11, floor((minRow - stripH - numH - bottomPad) / 3) - 1))
        let barH = max(thickness > 0 ? CGFloat(thickness) : autoBar, minBar)
        let moreH: CGFloat = 10
        let floorH = numH + bottomPad + strip

        func shown(_ i: Int, cap: Int?) -> [[BarSpan]] { cap.map { Array(fullRows[i].prefix($0)) } ?? fullRows[i] }
        func heights(cap: Int?) -> [CGFloat] {
            weeks.indices.map { i in
                let rows = shown(i, cap: cap)
                let hasHidden = cap.map { fullRows[i].count > $0 } ?? false
                return max(floorH, neededHeight(cells: weeks[i], rows: rows, barH: barH, strip: strip, annivMap: annivMap))
                    + (hasHidden ? moreH : 0)
            }
        }

        var cap: Int?
        var base = heights(cap: nil)
        if !scrollOnOverflow, base.reduce(0, +) > avail {
            var c = max(1, fullRows.map(\.count).max() ?? 1)
            while c > 1, heights(cap: c).reduce(0, +) > avail { c -= 1 }
            cap = c
            base = heights(cap: c)
        }
        // 余った高さは、少ない週から順にそろえて配る(予定が入りきるなら、全部の週が同じ高さ。
        // 高くなるのは、必要な高さが、そろえた高さを超える週だけ)
        let level = Self.levelingHeight(base, avail: avail)
        let rows = weeks.indices.map { shown($0, cap: cap) }
        let hidden: [[Int]] = weeks.indices.map { i in
            (0..<7).map { col in
                func covering(_ list: [[BarSpan]]) -> Int {
                    list.reduce(0) { $0 + $1.filter { $0.col <= col && col < $0.col + $0.span }.count }
                }
                return covering(fullRows[i]) - covering(rows[i])
            }
        }
        return MonthLayout(barH: barH, rows: rows, hidden: hidden, heights: base.map { max($0, level) })
    }

    /// 週ごとの必要な高さ(need)を満たしたまま、合計が avail になるように、低い週をそろえる高さ。
    /// 必要な高さの合計が avail 以上なら、そろえない(0)
    static func levelingHeight(_ need: [CGFloat], avail: CGFloat) -> CGFloat {
        guard !need.isEmpty, need.reduce(0, +) < avail else { return 0 }
        var low: CGFloat = 0, high = avail
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if need.reduce(0, { $0 + max($1, mid) }) > avail { high = mid } else { low = mid }
        }
        return low
    }

    /// 1週ぶんに必要な高さ。記念日のアイコンがある日は、その日のバーの下にもう1本ぶん確保する
    /// (その日にバーが1本もないときは確保しない。予定のない週の高さが、アイコンのある週だけ変わらないように)
    private func neededHeight(cells: [String], rows: [[BarSpan]], barH: CGFloat, strip: CGFloat,
                              annivMap: [String: [Anniversary]]) -> CGFloat {
        let lane = barH + barGap
        var h = numH + CGFloat(rows.count) * lane + bottomPad + strip
        for col in 0..<7 where annivMap[cells[col]] != nil {
            let used = rows.indices.filter { r in rows[r].contains { $0.col <= col && col < $0.col + $0.span } }
                .map { $0 + 1 }.max() ?? 0
            if used > 0 { h = max(h, numH + CGFloat(used) * lane + stripH) }
        }
        return h
    }

    /// ドラッグ中の予定を ds に置くと、時間つきの他の予定と重なるか
    private func dropConflicts(_ ds: String) -> Bool {
        guard let id = DragState.shared.draggingId, let m = store.dropPreview(id: id, on: ds) else { return false }
        return DropCheck.overlaps(moved: m, others: store.events)
    }

    private func dayCell(_ ds: String, conflict: Bool, annivs: [Anniversary], cellW: CGFloat) -> some View {
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
                let alarms = store.alarmCount(on: ds)
                if alarms > 0 {
                    // ベルの右に、2 個目からは「+1」のように、同じ色で個数を添える
                    HStack(spacing: 1) {
                        Image(systemName: "bell.fill").font(.app(9))
                        if alarms > 1 { Text("+\(alarms - 1)").font(.app(8, weight: .bold)) }
                    }
                    .foregroundStyle(Theme.alarm)
                    .padding(.trailing, store.hasPayday(on: ds) ? 2 : 3)
                    .accessibilityLabel("アラーム \(alarms)件")
                }
                // 給料日のコインはセルの右上の角に付ける(アラームはその左)。小さいので、カレンダー上では押せない(予定一覧の上のチップから開く)
                if store.hasPayday(on: ds) {
                    PaydayCoinButton()
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
            // セルの幅を4等分した枠に1個ずつ、週計の行と同じ高さの帯で右下に右詰めで並べる。
            // 足りない分は週の高さを広げて確保している
            HStack(spacing: 0) {
                ForEach(annivs.prefix(4)) { a in
                    // 小さいので、カレンダー上では押せない(タップは日付セルに通す。詳細は予定一覧の上から)
                    AnniversaryIcon(icon: a.icon, color: a.color, size: LayoutMath.slotIconSize)
                        .frame(width: cellW / 4, height: stripH)
                        .accessibilityLabel(a.name)
                }
            }
            .allowsHitTesting(false)
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
/// 給料日のコイン。小さいので、押せない見た目だけのアイコン(タップは日付セルに通る)
struct PaydayCoinButton: View {
    private let gold = Color(red: 0.95, green: 0.7, blue: 0.1)

    var body: some View {
        Image("CoinStack")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: LayoutMath.slotIconSize, height: LayoutMath.slotIconSize)
                .foregroundStyle(gold)
            // マスの横幅の1/4(約14pt)の枠の中央に、記念日アイコンと同じ大きさで置く。枠線には被らない
            .frame(width: 14, height: LayoutMath.numH)
        .allowsHitTesting(false)
        .accessibilityLabel("給料日")
    }
}
