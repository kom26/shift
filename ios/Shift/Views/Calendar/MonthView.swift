import SwiftUI

struct MonthView: View {
    @Environment(Store.self) private var store
    @Environment(Holidays.self) private var holidays
    let anchor: String
    let startMonday: Bool
    let onSelectDay: (String) -> Void
    let onSelectEvent: (ShiftEvent) -> Void
    let onDropEvent: (String, String) -> Void

    private let numH: CGFloat = 22
    private let barH: CGFloat = 14

    var body: some View {
        let ym = Rules.ymd(anchor)
        let weeks = Rules.monthWeeks(year: ym.year, month: ym.month, startMonday: startMonday)
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
            ForEach(weeks.indices, id: \.self) { i in
                weekRow(weeks[i]).frame(maxHeight: .infinity)
                Divider()
            }
        }
    }

    private func weekRow(_ cells: [String?]) -> some View {
        let rows = SpanLayout.rows(events: store.visibleEvents, weekCells: cells)
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
            }
            .dropDestination(for: String.self) { ids, location in
                guard let id = ids.first else { return false }
                guard w > 0 else { return false }
                let col = min(6, max(0, Int(location.x / w)))
                guard let ds = cells[col] else { return false }
                onDropEvent(id, ds)
                return true
            }
        }
        .clipped()
    }

    @ViewBuilder
    private func dayCell(_ ds: String?) -> some View {
        if let ds {
            let holiday = holidays.name(on: ds)
            let type = Rules.dayType(ds, isHoliday: holiday != nil)
            let isToday = ds == Rules.today()
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 2) {
                    Text("\(Rules.ymd(ds).day)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isToday ? Color.white : type.color)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(isToday ? Theme.accent : Color.clear, in: Circle())
                    if let holiday {
                        Text(holiday).font(.system(size: 7)).foregroundStyle(Theme.sunday).lineLimit(1)
                    }
                }
                .frame(height: numH, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.leading, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onSelectDay(ds) }
        } else {
            Color.clear
        }
    }
}
