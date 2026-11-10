import Foundation
import Testing
@testable import Shift

struct TaskItemTests {
    private func make() -> Store {
        let name = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).json")
        return Store(fileURL: url, defaults: UserDefaults(suiteName: name)!)
    }

    private func task(_ id: String, start: String? = nil, startTime: String? = nil,
                      due: String? = nil, dueTime: String? = nil, done: Bool = false) -> TaskItem {
        TaskItem(id: id, title: id, color: "#bf8df2", startDate: start, startTime: startTime,
                 dueDate: due, dueTime: dueTime, done: done)
    }

    @Test func kindsFollowDates() {
        #expect(task("a").isPlain)
        #expect(!task("a", start: "2026-12-08").isPlain)
        #expect(task("a", due: "2026-12-11").hasDue)
    }

    @Test func markersSkipDoneAndSplitStartAndDue() {
        let store = make()
        store.saveTask(task("a", start: "2026-12-08", due: "2026-12-11"))
        store.saveTask(task("b", due: "2026-12-12", done: true))
        store.saveTask(task("c"))
        let m = store.taskMarkers()
        #expect(m.count == 2)
        #expect(m[0].taskMarker == TaskMarker(taskId: "a", isStart: true))
        #expect(m[1].taskMarker == TaskMarker(taskId: "a", isStart: false))
        #expect(m[0].startDate == "2026-12-08" && m[0].endDate == "2026-12-08")
    }

    @Test func monthLinksStartAndDueIntoOneBar() {
        let store = make()
        store.saveTask(task("a", start: "2026-12-08", due: "2026-12-11"))
        store.saveTask(task("b", start: "2026-12-08", due: "2026-12-08"))
        let m = store.taskMarkers(linked: true)
        let link = m.first { $0.taskMarker?.taskId == "a" }
        #expect(m.filter { $0.taskMarker?.taskId == "a" }.count == 1)
        #expect(link?.taskMarker?.isLink == true)
        #expect(link?.startDate == "2026-12-08" && link?.endDate == "2026-12-11")
        // 同じ日の開始と締切は、つながずに 2 つのタグ
        #expect(m.filter { $0.taskMarker?.taskId == "b" }.count == 2)
    }

    @Test func movingOneEndKeepsTheOtherAndPushesWhenCrossing() {
        let store = make()
        store.saveTask(task("a", start: "2026-12-08", due: "2026-12-11"))
        store.moveTask(id: "a", isStart: false, to: "2026-12-15")
        #expect(store.task(id: "a")?.startDate == "2026-12-08" && store.task(id: "a")?.dueDate == "2026-12-15")
        store.moveTask(id: "a", isStart: true, to: "2026-12-05")
        #expect(store.task(id: "a")?.startDate == "2026-12-05" && store.task(id: "a")?.dueDate == "2026-12-15")
        // 開始を締切より後ろへ動かすと、締切も同じ日まで動く
        store.moveTask(id: "a", isStart: true, to: "2026-12-20")
        #expect(store.task(id: "a")?.startDate == "2026-12-20" && store.task(id: "a")?.dueDate == "2026-12-20")
    }

    @Test func timelessMarkersGoToAllDayAndTimedBecomeLines() {
        let store = make()
        store.saveTask(task("a", start: "2026-12-08", startTime: "14:00", due: "2026-12-08"))
        #expect(store.taskMarkers(timelessOnly: true).count == 1)
        #expect(store.taskMarkers(timelessOnly: true)[0].taskMarker?.isStart == false)
        let lines = store.taskLines(on: "2026-12-08")
        #expect(lines.count == 1)
        #expect(lines[0].minutes == 14 * 60 && lines[0].isStart)
    }

    @Test func dayRowsKeepDoneItemsAndPutTimedFirst() {
        let store = make()
        store.saveTask(task("a", due: "2026-12-08", done: true))
        store.saveTask(task("b", due: "2026-12-08", dueTime: "18:00"))
        let rows = store.taskRows(on: "2026-12-08")
        #expect(rows.map(\.task.id) == ["b", "a"])
        #expect(rows[1].timeText == "締切")
        #expect(rows[0].timeText == "18:00")
    }

    @Test func manageTabsAndBadges() {
        let store = make()
        store.saveTask(task("p"))
        store.saveTask(task("s", start: "2026-12-02"))
        store.saveTask(task("d1", due: "2026-12-19", done: true))
        store.saveTask(task("d2", start: "2026-12-08", due: "2026-12-11"))
        #expect(store.taskRows(kind: .plain).map(\.task.id) == ["p"])
        #expect(store.taskRows(kind: .start).map(\.task.id) == ["s", "d2"])
        #expect(store.taskRows(kind: .due).map(\.task.id) == ["d2", "d1"])
        #expect(store.openTaskCount(kind: .due) == 1)
        store.toggleTaskDone(id: "d1")
        #expect(store.openTaskCount(kind: .due) == 2)
    }

    @Test func tasksSurviveSnapshotAndWipe() {
        let store = make()
        store.saveTask(task("a", due: "2026-12-11"))
        let snap = store.syncSnapshot()
        #expect(snap.tasks?.count == 1)
        #expect(!store.isPristine)
        store.wipeLocalData()
        #expect(store.tasks.isEmpty)
        store.applySnapshot(snap)
        #expect(store.tasks.count == 1)
    }

    @Test func decodesOldJSONWithoutDone() throws {
        let json = ##"{"id":"x","title":"t","color":"#fff","dueDate":"2026-12-11"}"##
        let t = try JSONDecoder().decode(TaskItem.self, from: Data(json.utf8))
        #expect(!t.done && t.dueDate == "2026-12-11" && t.startDate == nil)
    }
}

struct TaskDateOrderTests {
    @Test func dueBeforeStartIsPulledToTheStartDay() {
        let r = TaskItem.orderedDates(start: "2026-11-11", due: "2026-11-10")
        #expect(r.start == "2026-11-11" && r.due == "2026-11-11")
    }

    @Test func orderedOrMissingDatesAreKept() {
        #expect(TaskItem.orderedDates(start: "2026-11-10", due: "2026-11-11").due == "2026-11-11")
        #expect(TaskItem.orderedDates(start: nil, due: "2026-11-10").due == "2026-11-10")
        #expect(TaskItem.orderedDates(start: "2026-11-10", due: nil).start == "2026-11-10")
    }
}
