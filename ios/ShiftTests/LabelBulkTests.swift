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

struct SharedAttachmentTests {
    @Test func calendarImageIdsCarryTheirCalendar() {
        let id = AttachmentStore.calendarImageId(calendarId: "cal123")
        #expect(id.hasPrefix(AttachmentStore.calendarPrefix))
        #expect(AttachmentStore.calendarId(of: id) == "cal123")
        #expect(AttachmentStore.calendarId(of: UUID().uuidString) == nil)
    }

    @Test func sharedEventCarriesMemoUrlAndImageToTheCalendarView() {
        var e = SharedEvent(id: "cal_x", ownerUid: "u", sourceKey: SharedEvent.calendarKey, title: "会議", startDate: "2026-12-08",
                            endDate: "2026-12-08", startTime: nil, endTime: nil, allDay: true, name: "", color: "#bec1cc")
        e.memo = "資料は前日まで"
        e.url = "https://example.com"
        e.imageId = "cal~c~x"
        let shown = e.shiftEvent()
        #expect(shown.memo == "資料は前日まで" && shown.url == "https://example.com" && shown.imageId == "cal~c~x")
        let moved = e.moved(to: "2026-12-09")
        #expect(moved.memo == e.memo && moved.url == e.url && moved.imageId == e.imageId)
    }
}

struct YearGroupTests {
    private func event(_ id: String, _ date: String?) -> ShiftEvent { ev(id, date) }

    @Test func groupsBreakWhereTheYearChanges() {
        let g = LabelEventsView.yearGroups([event("a", "2026-12-20"), event("b", "2026-12-23"), event("c", "2027-02-08")])
        #expect(g.map(\.title) == ["2026年", "2027年"])
        #expect(g[0].events.map(\.id) == ["a", "b"] && g[1].events.map(\.id) == ["c"])
    }

    @Test func newestFirstListKeepsItsOrderAndUndatedGoesLast() {
        let g = LabelEventsView.yearGroups([event("c", "2027-02-08"), event("a", "2026-12-20"), event("n", nil)])
        #expect(g.map(\.title) == ["2027年", "2026年", "日付なし"])
    }
}

struct TaskLinkDotsTests {
    @Test func linkIsOffByDefaultAndOnlyChosenTasksAreLinked() {
        let name = UUID().uuidString
        let store = Store(fileURL: FileManager.default.temporaryDirectory.appending(path: "\(name).json"), defaults: UserDefaults(suiteName: name)!)
        var a = TaskItem.new(startDate: "2026-12-08", dueDate: "2026-12-11")
        a.id = "a"
        var b = a
        b.id = "b"
        b.linkDots = true
        store.saveTask(a)
        store.saveTask(b)
        let m = store.taskMarkers(linked: true)
        #expect(m.filter { $0.taskMarker?.taskId == "a" }.count == 2)
        #expect(m.filter { $0.taskMarker?.taskId == "b" && $0.taskMarker?.isLink == true }.count == 1)
    }
}
