import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct WeekView: View {
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

    private let timeW: CGFloat = 22
    private let barH: CGFloat = 20

    var body: some View {
        let start = Rules.weekStart(of: anchor, startMonday: startMonday)
        let days = (0..<7).map { Rules.addDays(start, $0) }
        let conflictDays: Set<String> = conflictWarningOn ? Conflicts.days(events: store.events, minGapMinutes: conflictGapMinutes) : []
        let allDayRows = SpanLayout.rows(events: store.visibleEvents.filter(\.allDay), weekCells: days.map { Optional($0) })
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: timeW, height: 0)
                ForEach(days, id: \.self) { header($0, conflict: conflictDays.contains($0)) }
            }
            allDayRow(days: days, rows: allDayRows)
            Divider()
            grid(days, conflictDays: conflictDays)
            let b = Rules.monthBounds(of: anchor)
            let monthTotals = store.totals(from: b.first, to: b.last, isHoliday: { holidays.name(on: $0) != nil })
            if summaryOn {
                Divider()
                SummaryStrip(label: "週計", totals: store.totals(from: days[0], to: days[6], isHoliday: { holidays.name(on: $0) != nil }, orderBy: monthTotals.map(\.key)), emptyText: "データなし",
                             fill: Color(.systemBackground), labelColor: Color.secondary)
                    .frame(height: 18)
            } else {
                Divider()
            }
            SummaryStrip(label: "月計", totals: monthTotals, emptyText: "データなし",
                         fill: Theme.accentSoft, labelColor: Color.secondary)
                .frame(height: 20)
        }
        .background { MonthWatermark(number: Rules.ymd(days[3]).month) }
    }

    private func header(_ ds: String, conflict: Bool) -> some View {
        let holiday = holidays.name(on: ds)
        let type = Rules.dayType(ds, isHoliday: holiday != nil)
        let isToday = ds == Rules.today()
        return VStack(spacing: 1) {
            Text(Rules.weekdayLabels(startMonday: false)[Rules.weekday(ds)])
                .font(.app(9))
                .foregroundStyle(type.color)
            Text("\(Rules.ymd(ds).day)")
                .font(.app(13, weight: .semibold))
                .foregroundStyle(isToday ? Theme.accent : (type == .normal ? Color.primary : type.color))
            Text(holiday ?? " ")
                .font(.app(9))
                .foregroundStyle(Theme.sunday)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .overlay(alignment: .topTrailing) {
            if store.hasPayday(on: ds) {
                PaydayCoinButton { onSelectPayday(ds) }
            }
        }
        .background(conflict ? Color.red.opacity(0.16) : (isToday ? Theme.accentSoft : Color.clear))
        .overlay {
            if selectedDate == ds {
                Rectangle().strokeBorder(Theme.accent, lineWidth: 1.5)
            }
        }
    }

    @ViewBuilder
    private func allDayRow(days: [String], rows: [[BarSpan]]) -> some View {
        if rows.isEmpty {
            EmptyView()
        } else {
            GeometryReader { geo in
                let colW = (geo.size.width - timeW) / 7
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        Color.clear.frame(width: timeW)
                        ForEach(0..<7, id: \.self) { i in
                            (dropTarget == days[i] && !(dropMoved?.isTimedDrop ?? false) ? Theme.accentSoft : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelectDay(days[i]) }
                                .onLongPressGesture(minimumDuration: 0.45) {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    onLongPressDay(days[i])
                                }
                        }
                    }
                    SpanBars(rows: rows, colW: colW, barH: barH, leading: timeW, onSelect: onSelectEvent)
                }
                .onDrop(of: [.plainText], delegate: EventDropDelegate(
                    resolve: { p in
                        guard colW > 0 else { return nil }
                        return days[min(6, max(0, Int((p.x - timeW) / colW)))]
                    },
                    target: $dropTarget,
                    onDrop: onDropEvent))
            }
            .frame(height: CGFloat(rows.count) * (barH + 2) + 4)
            .clipped()
        }
    }

    private func grid(_ days: [String], conflictDays: Set<String>) -> some View {
        GeometryReader { geo in
            let colW = (geo.size.width - timeW) / 7
            let H = geo.size.height
            let timed = store.visibleEvents.filter { !$0.allDay }
            ZStack(alignment: .topLeading) {
                ForEach(0..<48, id: \.self) { k in
                    Rectangle()
                        .fill(Color(.separator).opacity(k % 2 == 0 ? 0.5 : 0.2))
                        .frame(width: geo.size.width - timeW, height: 0.5)
                        .offset(x: timeW, y: H * CGFloat(k) / 48)
                }
                ForEach(1..<24, id: \.self) { h in
                    Text("\(h)")
                        .font(.app(8).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: timeW - 2, alignment: .trailing)
                        .offset(y: H * CGFloat(h) / 24 - 5)
                }
                ForEach(0..<7, id: \.self) { i in
                    let ds = days[i]
                    column(ds, events: timed, colW: colW, H: H)
                        .frame(width: colW, height: H, alignment: .topLeading)
                        .background(dropTarget == ds && !(dropMoved?.isTimedDrop ?? false) ? Theme.accentSoft : (conflictDays.contains(ds) ? Color.red.opacity(0.10) : Color.clear))
                        .overlay(alignment: .topLeading) { dropSegment(ds, colW: colW, H: H) }
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color(.separator).opacity(0.5)).frame(width: 0.5)
                        }
                        .onDrop(of: [.plainText], delegate: EventDropDelegate(
                            resolve: { _ in ds },
                            target: $dropTarget,
                            onDrop: onDropEvent))
                        .offset(x: timeW + colW * CGFloat(i))
                }
            }
        }
        .clipped()
    }

    /// ドラッグ中の予定を dropTarget に置いたときの姿
    private var dropMoved: ShiftEvent? {
        guard let t = dropTarget, let id = DragState.shared.draggingId else { return nil }
        return store.dropPreview(id: id, on: t)
    }

    /// 予定がハマる時間帯だけを点線と塗りで示す(他の予定と重なるなら赤)
    @ViewBuilder
    private func dropSegment(_ ds: String, colW: CGFloat, H: CGFloat) -> some View {
        if let m = dropMoved, m.isTimedDrop, let seg = Rules.timedSegment(m, on: ds) {
            let bad = DropCheck.overlaps(moved: m, others: store.events)
            let tint: Color = bad ? .red : Theme.accent
            let shape = RoundedRectangle(cornerRadius: 3)
            shape.fill(bad ? Color.red.opacity(0.22) : Theme.accentSoft)
                .overlay(shape.strokeBorder(tint, style: StrokeStyle(lineWidth: 2, dash: [4, 3])))
                .frame(width: max(0, colW - 2), height: H * CGFloat(seg.height))
                .offset(x: 1, y: H * CGFloat(seg.top))
                .allowsHitTesting(false)
        }
    }

    private func column(_ ds: String, events: [ShiftEvent], colW: CGFloat, H: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())
                .onTapGesture { onSelectDay(ds) }
                .onLongPressGesture(minimumDuration: 0.45) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onLongPressDay(ds)
                }
            ForEach(events) { ev in
                if let seg = Rules.timedSegment(ev, on: ds) {
                    let h = max(14, H * CGFloat(seg.height))
                    block(ev, h: h)
                        .frame(width: max(0, colW - 2), height: h)
                        .onTapGesture { onSelectEvent(ev) }
                        .eventMenu(for: ev, store: store, onEdit: onSelectEvent) {
                            blockPreview(ev, w: max(0, colW - 2), h: h)
                        }
                        .draggable(DragState.shared.begin(ev.id))
                        .offset(x: 1, y: H * CGFloat(seg.top))
                }
            }
            if ds == Rules.today() {
                TimelineView(.everyMinute) { ctx in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: ctx.date)
                    let mins = CGFloat((c.hour ?? 0) * 60 + (c.minute ?? 0))
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(Color.red).frame(width: colW, height: 2)
                        Circle().fill(Color.red).frame(width: 8, height: 8).offset(x: -4, y: -3)
                    }
                    .offset(y: H * mins / 1440 - 1)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func blockPreview(_ ev: ShiftEvent, w: CGFloat, h: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3)
        let time = Rules.timeLabel(ev)
        return VStack(alignment: .leading, spacing: 0) {
            Text(ev.title)
                .font(.bar(10, weight: .bold))
                .lineLimit(1)
                .fixedSize()
            if !time.isEmpty {
                Text(time)
                    .font(.bar(9, weight: .bold))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .foregroundStyle(EventColor.text(ev.color))
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(minWidth: w, minHeight: h, alignment: .topLeading)
        .background(EventColor.fill(ev.color), in: shape)
        .background(Color(.systemBackground), in: shape)
        .clipShape(shape)
    }

    private func block(_ ev: ShiftEvent, h: CGFloat) -> some View {
        return VStack(alignment: .leading, spacing: 0) {
            Text(ev.title)
                .font(.bar(10, weight: .bold))
                .lineLimit(2)
            if h > 30 {
                Text(Rules.timeLabel(ev))
                    .font(.bar(9))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(EventColor.text(ev.color))
        .padding(2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(EventColor.fill(ev.color), in: RoundedRectangle(cornerRadius: 3))
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(hex: ev.color).opacity(0.55), lineWidth: 1))
    }
}
