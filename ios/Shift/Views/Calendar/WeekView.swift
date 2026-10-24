import SwiftUI
import UniformTypeIdentifiers

struct WeekView: View {
    @Environment(Store.self) private var store
    @Environment(Holidays.self) private var holidays
    let anchor: String
    let startMonday: Bool
    let summaryOn: Bool
    let onSelectDay: (String) -> Void
    let onSelectEvent: (ShiftEvent) -> Void
    let onDropEvent: (String, String) -> Void

    @State private var dropTarget: String?

    private let timeW: CGFloat = 22
    private let barH: CGFloat = 20

    var body: some View {
        let start = Rules.weekStart(of: anchor, startMonday: startMonday)
        let days = (0..<7).map { Rules.addDays(start, $0) }
        let allDayRows = SpanLayout.rows(events: store.visibleEvents.filter(\.allDay), weekCells: days.map { Optional($0) })
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: timeW, height: 0)
                ForEach(days, id: \.self) { header($0) }
            }
            allDayRow(days: days, rows: allDayRows)
            Divider()
            grid(days)
            if summaryOn {
                let b = Rules.monthBounds(of: anchor)
                Divider()
                SummaryStrip(label: "週計", totals: store.totals(from: days[0], to: days[6]), emptyText: "データなし")
                    .frame(height: 24)
                Divider()
                SummaryStrip(label: "月計", totals: store.totals(from: b.first, to: b.last), emptyText: "データなし")
                    .frame(height: 24)
            }
        }
        .background { MonthWatermark(number: Rules.ymd(days[3]).month) }
    }

    private func header(_ ds: String) -> some View {
        let holiday = holidays.name(on: ds)
        let type = Rules.dayType(ds, isHoliday: holiday != nil)
        let isToday = ds == Rules.today()
        return VStack(spacing: 1) {
            Text(Rules.weekdayLabels(startMonday: false)[Rules.weekday(ds)])
                .font(.system(size: 9))
                .foregroundStyle(type.color)
            Text("\(Rules.ymd(ds).day)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isToday ? Theme.accent : (type == .normal ? Color.primary : type.color))
            Text(holiday ?? " ")
                .font(.system(size: 9))
                .foregroundStyle(Theme.sunday)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(isToday ? Theme.accentSoft : Color.clear)
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
                            (dropTarget == days[i] ? Theme.accentSoft : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelectDay(days[i]) }
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

    private func grid(_ days: [String]) -> some View {
        GeometryReader { geo in
            let colW = (geo.size.width - timeW) / 7
            let H = geo.size.height
            ZStack(alignment: .topLeading) {
                ForEach(0..<48, id: \.self) { k in
                    Rectangle()
                        .fill(Color(.separator).opacity(k % 2 == 0 ? 0.5 : 0.2))
                        .frame(width: geo.size.width - timeW, height: 0.5)
                        .offset(x: timeW, y: H * CGFloat(k) / 48)
                }
                ForEach(1..<24, id: \.self) { h in
                    Text("\(h)")
                        .font(.system(size: 8).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: timeW - 2, alignment: .trailing)
                        .offset(y: H * CGFloat(h) / 24 - 5)
                }
                ForEach(0..<7, id: \.self) { i in
                    let ds = days[i]
                    column(ds, colW: colW, H: H)
                        .frame(width: colW, height: H, alignment: .topLeading)
                        .background(dropTarget == ds ? Theme.accentSoft : Color.clear)
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

    private func column(_ ds: String, colW: CGFloat, H: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle()).onTapGesture { onSelectDay(ds) }
            ForEach(store.visibleEvents.filter { !$0.allDay }) { ev in
                if let seg = Rules.timedSegment(ev, on: ds) {
                    let h = max(14, H * CGFloat(seg.height))
                    block(ev, h: h)
                        .frame(width: max(0, colW - 2), height: h)
                        .onTapGesture { onSelectEvent(ev) }
                        .eventMenu(for: ev, store: store, previewCornerRadius: 3, onEdit: onSelectEvent)
                        .draggable(ev.id)
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

    private func block(_ ev: ShiftEvent, h: CGFloat) -> some View {
        let color = Color(hex: ev.color)
        return VStack(alignment: .leading, spacing: 0) {
            Text(ev.title)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(2)
                .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
            if h > 30 {
                Text(Rules.timeLabel(ev))
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
            }
        }
        .foregroundStyle(.white)
        .padding(2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(color, lineWidth: 1))
    }
}
