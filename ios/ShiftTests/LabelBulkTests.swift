import Foundation
import Testing
@testable import Shift

struct LabelBulkTests {
    private func make() -> Store {
        let name = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).json")
        return Store(fileURL: url, defaults: UserDefaults(suiteName: name)!)
    }

    private func event(_ id: String, _ date: String, label: String?, color: String = EventLabel.noneColor, own: Bool? = nil) -> ShiftEvent {
        var e = ev(id, date)
        e.labelId = label
        e.color = color
        e.ownColor = own
        return e
    }

    @Test func labelEventsAreSortedByDateAndCanBeReversed() {
        let s = make()
        let l = s.addLabel(name: "空き", color: "#bcd6f7")!
        s.save(event("b", "2026-12-20", label: l.id))
        s.save(event("a", "2026-12-05", label: l.id))
        s.save(event("c", "2026-12-10", label: nil))
        #expect(s.labelEvents(l.id).map(\.id) == ["a", "b"])
        #expect(s.labelEvents(l.id, oldestFirst: false).map(\.id) == ["b", "a"])
        #expect(s.labelEvents(nil).map(\.id) == ["c"])
    }

    @Test func movingFollowsTheNewLabelColorUnlessOwnColor() {
        let s = make()
        let from = s.addLabel(name: "空き", color: "#bcd6f7")!
        let to = s.addLabel(name: "医療", color: "#bfeee0")!
        s.save(event("follow", "2026-12-05", label: from.id, color: from.color))
        s.save(event("own", "2026-12-06", label: from.id, color: "#ff0000", own: true))
        s.setLabel(eventIds: ["follow", "own"], to: to.id)
        let a = s.events.first { $0.id == "follow" }!, b = s.events.first { $0.id == "own" }!
        #expect(a.labelId == to.id && a.color == to.color)
        #expect(b.labelId == to.id && b.color == "#ff0000")
    }

    @Test func movingToNoneUsesTheGrayAndOnlyTouchesTheChosenEvents() {
        let s = make()
        let l = s.addLabel(name: "空き", color: "#bcd6f7")!
        s.save(event("x", "2026-12-05", label: l.id, color: l.color))
        s.save(event("y", "2026-12-06", label: l.id, color: l.color))
        s.setLabel(eventIds: ["x"], to: nil)
        #expect(s.events.first { $0.id == "x" }!.labelId == nil)
        #expect(s.events.first { $0.id == "x" }!.color == EventLabel.noneColor)
        #expect(s.events.first { $0.id == "y" }!.labelId == l.id)
    }

    @Test func bulkDeleteRemovesOnlyTheChosenEvents() {
        let s = make()
        s.save(event("a", "2026-12-05", label: nil))
        s.save(event("b", "2026-12-06", label: nil))
        s.save(event("c", "2026-12-07", label: nil))
        s.deleteEvents(ids: ["a", "c"])
        #expect(s.events.map(\.id) == ["b"])
    }
}
