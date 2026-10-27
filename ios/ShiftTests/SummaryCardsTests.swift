import Foundation
import Testing
@testable import Shift

struct SummaryCardsTests {
    private func make() -> Store {
        let name = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).json")
        return Store(fileURL: url, defaults: UserDefaults(suiteName: name)!)
    }

    @Test func hoursDelta() {
        #expect(DeltaFormat.hours(2.5).text == "+2.5h ↑")
        #expect(DeltaFormat.hours(2.5).trend == .up)
        #expect(DeltaFormat.hours(-1).text == "-1h ↓")
        #expect(DeltaFormat.hours(-1).trend == .down)
        #expect(DeltaFormat.hours(0).text == "±0h")
        #expect(DeltaFormat.hours(0).trend == .flat)
        #expect(DeltaFormat.hours(0.04).text == "±0h")
        #expect(DeltaFormat.hours(3.04).text == "+3h ↑")
    }

    @Test func yenDelta() {
        #expect(DeltaFormat.yen(12000).text == "+¥12,000 ↑")
        #expect(DeltaFormat.yen(-3000).text == "-¥3,000 ↓")
        #expect(DeltaFormat.yen(0).text == "±¥0")
        #expect(DeltaFormat.yen(0).trend == .flat)
    }

    private func seeded() -> Store {
        let store = make()
        store.save(ev("a", "2026-10-20", allDay: false, st: "09:00", et: "13:00", wh: 4))
        store.save(ev("b", "2026-10-20", allDay: false, st: "14:00", et: "17:00", wh: 3))
        store.save(ev("c", "2026-10-14", allDay: false, st: "09:00", et: "14:00", wh: 5))
        store.save(ev("d", "2026-09-10", allDay: false, st: "09:00", et: "15:00", wh: 6))
        attachWorkplaces(store)
        return store
    }

    @Test func summaryCardsWithSelectedDate() {
        let s = seeded().summaryCards(selectedDate: "2026-10-21", today: "2026-10-14",
                                      anchor: "2026-10-15", startMonday: false)
        #expect(s.weekStart == "2026-10-18")
        #expect(s.weekEnd == "2026-10-24")
        #expect(s.weekHours == 7)
        #expect(s.prevWeekHours == 5)
        #expect(s.monthHours == 12)
        #expect(s.prevMonthHours == 6)
    }

    @Test func summaryCardsFallsBackToToday() {
        let s = seeded().summaryCards(selectedDate: nil, today: "2026-10-14",
                                      anchor: "2026-10-15", startMonday: false)
        #expect(s.weekStart == "2026-10-11")
        #expect(s.weekEnd == "2026-10-17")
        #expect(s.weekHours == 5)
    }

    @Test func weekLabelSundayStart() {
        let s = seeded().summaryCards(selectedDate: "2026-10-21", today: "2026-10-14",
                                      anchor: "2026-10-15", startMonday: false)
        #expect(s.weekLabel == "10月18日(日)〜24日(土)")
        #expect(s.monthLabel == "2026年10月")
        #expect(s.payLabel == "2026年10月勤務分")
    }

    @Test func weekLabelMondayStart() {
        let s = seeded().summaryCards(selectedDate: "2026-10-21", today: "2026-10-14",
                                      anchor: "2026-10-15", startMonday: true)
        #expect(s.weekLabel == "10月19日(月)〜25日(日)")
    }

    @Test func weekLabelCrossMonth() {
        let s = seeded().summaryCards(selectedDate: "2026-09-30", today: "2026-10-14",
                                      anchor: "2026-10-15", startMonday: false)
        #expect(s.weekLabel == "9月27日(日)〜10月3日(土)")
    }
}
