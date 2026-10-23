import Foundation
@testable import Shift

func ev(_ id: String, _ start: String?, _ end: String? = nil, color: String = "#6366f1",
        allDay: Bool = true, placed: Bool = true, st: String? = nil, et: String? = nil,
        wh: Double? = nil) -> ShiftEvent {
    ShiftEvent(id: id, title: id, memo: "", color: color, startDate: start, endDate: end ?? start,
               placed: placed, allDay: allDay, startTime: st, endTime: et, workHours: wh)
}
