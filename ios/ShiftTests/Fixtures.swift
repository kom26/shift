import Foundation
@testable import Shift

func ev(_ id: String, _ start: String?, _ end: String? = nil, color: String = "#6366f1",
        allDay: Bool = true, placed: Bool = true, st: String? = nil, et: String? = nil,
        wh: Double? = nil) -> ShiftEvent {
    ShiftEvent(id: id, title: id, memo: "", color: color, startDate: start, endDate: end ?? start,
               placed: placed, allDay: allDay, startTime: st, endTime: et, workHours: wh)
}

/// 保存済みの予定を色ごとの職場に結びつける(職場なしの予定は集計されないため)
func attachWorkplaces(_ store: Store) {
    for e in store.events where e.workplaceId == nil && store.workplace(for: e) == nil {
        if !store.workplaces.contains(where: { $0.id == e.color }) {
            store.addWorkplace(Workplace(id: e.color, name: "wp" + e.color, color: e.color))
        }
        var copy = e
        copy.workplaceId = e.color
        store.save(copy)
    }
}
