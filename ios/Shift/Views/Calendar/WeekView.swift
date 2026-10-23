import SwiftUI

struct WeekView: View {
    @Environment(Store.self) private var store
    @Environment(Holidays.self) private var holidays
    let anchor: String
    let startMonday: Bool
    let onSelectDay: (String) -> Void
    let onSelectEvent: (ShiftEvent) -> Void

    private let timeW: CGFloat = 26
    private let barH: CGFloat = 14

    var body: some View {
        let start = Rules.weekStart(of: anchor, startMonday: startMonday)
        let days = (0..<7).map { Rules.addDays(start, $0) }
        let allDayRows = SpanLayout.rows(events: store.visibleEvents.filter(\.allDay), weekCells: days)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: timeW)
                ForEach(days, id: \.self) { header($0) }
            }
            GeometryReader { geo in
                SpanBars(rows: allDayRows, colW: (geo.size.width - timeW) / 7, barH: barH,
                         leading: timeW, onSelect: onSelectEvent)
            }
            .frame(height: allDayRows.isEmpty ? 0 : CGFloat(allDayRows.count) * (barH + 2) + 4)
            Divider()
            grid(days)
        }
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
                .foregroundStyle(isToday ? Color.white : (type == .normal ? Color.primary : type.color))
                .frame(minWidth: 22, minHeight: 22)
                .background(isToday ? Theme.accent : Color.clear, in: Circle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onSelectDay(ds) }
    }

    private func grid(_ days: [String]) -> some View {
        GeometryReader { geo in
            let colW = (geo.size.width - timeW) / 7
            let H = geo.size.height
            ZStack(alignment: .topLeading) {
                ForEach(0..<24, id: \.self) { h in
                    Rectangle()
                        .fill(Color(.separator).opacity(h % 3 == 0 ? 0.7 : 0.25))
                        .frame(width: geo.size.width - timeW, height: 0.5)
                        .offset(x: timeW, y: H * CGFloat(h) / 24)
                    if h % 3 == 0 {
                        Text("\(h)")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .frame(width: timeW - 4, alignment: .trailing)
                            .offset(y: H * CGFloat(h) / 24 - 5)
                    }
                }
                ForEach(0..<7, id: \.self) { i in
                    column(days[i], colW: colW, H: H)
                        .frame(width: colW, height: H, alignment: .topLeading)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color(.separator).opacity(0.5)).frame(width: 0.5)
                        }
                        .offset(x: timeW + colW * CGFloat(i))
                }
            }
        }
    }

    private func column(_ ds: String, colW: CGFloat, H: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle()).onTapGesture { onSelectDay(ds) }
            ForEach(store.visibleEvents.filter { !$0.allDay }) { ev in
                if let seg = Rules.timedSegment(ev, on: ds) {
                    let h = max(14, H * seg.height)
                    block(ev, h: h)
                        .frame(width: colW - 2, height: h)
                        .offset(x: 1, y: H * seg.top)
                        .onTapGesture { onSelectEvent(ev) }
                }
            }
        }
    }

    private func block(_ ev: ShiftEvent, h: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ev.title).font(.system(size: 8, weight: .semibold)).lineLimit(2)
            if h > 28 {
                Text(Rules.timeLabel(ev)).font(.system(size: 7)).lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(hex: ev.color).opacity(0.9), in: RoundedRectangle(cornerRadius: 3))
    }
}
