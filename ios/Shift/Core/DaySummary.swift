import Foundation

struct DayEventRow: Identifiable {
    let event: ShiftEvent
    let isAllDay: Bool
    let isContinuation: Bool
    var id: String { event.id }
}

struct DaySummary {
    let date: String
    let paydays: [Store.PaymentRow]
    let events: [DayEventRow]
}

extension Store {
    func daySummary(date: String, isHoliday: (String) -> Bool = { _ in false }) -> DaySummary {
        var allDay: [DayEventRow] = []
        var timed: [(top: Double, row: DayEventRow)] = []
        for ev in events where ev.placed {
            guard let sd = ev.startDate else { continue }
            let cont = sd != date
            if ev.allDay {
                if Rules.dateInRange(date, sd, ev.endDate) {
                    allDay.append(DayEventRow(event: ev, isAllDay: true, isContinuation: cont))
                }
            } else if let seg = Rules.timedSegment(ev, on: date) {
                timed.append((seg.top, DayEventRow(event: ev, isAllDay: false, isContinuation: cont)))
            }
        }
        allDay.sort { $0.event.title < $1.event.title }
        timed.sort { $0.top != $1.top ? $0.top < $1.top : $0.row.event.title < $1.row.event.title }
        return DaySummary(date: date,
                          paydays: payments(onPayday: date, isHoliday: isHoliday),
                          events: allDay + timed.map(\.row))
    }
}
