import Foundation
import Testing
@testable import Shift

struct StoreTests {
    private func make() -> (store: Store, url: URL, defaults: UserDefaults, name: String) {
        let name = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).json")
        let defaults = UserDefaults(suiteName: name)!
        return (Store(fileURL: url, defaults: defaults), url, defaults, name)
    }

    @Test func savePersistsAcrossInstances() {
        let (store, url, defaults, _) = make()
        store.save(ev("a", "2026-10-20"))
        let reloaded = Store(fileURL: url, defaults: defaults)
        #expect(reloaded.events.map(\.id) == ["a"])
    }

    @Test func saveWithSameIdUpdates() {
        let (store, _, _, _) = make()
        store.save(ev("a", "2026-10-20"))
        var changed = ev("a", "2026-10-21")
        changed.title = "changed"
        store.save(changed)
        #expect(store.events.count == 1)
        #expect(store.events[0].title == "changed")
        #expect(store.events[0].startDate == "2026-10-21")
    }

    @Test func deleteRemovesEvent() {
        let (store, _, _, _) = make()
        store.save(ev("a", "2026-10-20"))
        store.delete(id: "a")
        #expect(store.events.isEmpty)
    }

    @Test func saveAndDuplicateKeepsOriginalAndAddsCopyWithNewId() {
        let (store, _, _, _) = make()
        store.save(ev("a", "2026-10-20"))
        var edited = ev("a", "2026-10-22")
        edited.title = "edited"
        store.saveAndDuplicate(edited)
        #expect(store.events.count == 2)
        #expect(store.events[0].id == "a")
        #expect(store.events[0].startDate == "2026-10-22")
        #expect(store.events[1].id != "a")
        #expect(store.events[1].title == "edited")
    }

    @Test func visibleEventsExcludeUnplacedAndFilteredWorkplaces() {
        let (store, _, _, _) = make()
        store.addWorkplace(Workplace(id: "w1", name: "A", color: "#ef4444"))
        store.addWorkplace(Workplace(id: "w2", name: "B", color: "#3b82f6"))
        var a = ev("a", "2026-10-20"); a.workplaceId = "w1"
        var b = ev("b", "2026-10-20"); b.workplaceId = "w2"
        store.save(a)
        store.save(b)
        store.save(ev("loose", "2026-10-20"))
        store.save(ev("un", nil, placed: false))
        #expect(store.visibleEvents.map(\.id) == ["a", "b", "loose"])
        store.toggleWorkplaceFilter("w1")
        #expect(store.visibleEvents.map(\.id) == ["a"])
        store.toggleWorkplaceFilter(Store.noWorkplaceKey)
        #expect(store.visibleEvents.map(\.id) == ["a", "loose"])
        store.toggleWorkplaceFilter("w1")
        #expect(store.visibleEvents.map(\.id) == ["loose"])
        store.clearWorkplaceFilter()
        #expect(store.visibleEvents.count == 3)
    }

    @Test func checkedWorkplacesPersist() {
        let (store, url, defaults, _) = make()
        store.toggleWorkplaceFilter("w1")
        store.toggleWorkplaceFilter(Store.noWorkplaceKey)
        let reloaded = Store(fileURL: url, defaults: defaults)
        #expect(reloaded.checkedWorkplaces == ["w1", ""])
    }

    @Test func rememberColorSkipsPresetsAndKeepsEightMostRecent() {
        let (store, _, _, _) = make()
        store.rememberColor(Store.defaultColors[0])
        #expect(store.customColors.isEmpty)
        for i in 0..<10 { store.rememberColor(String(format: "#0000%02x", i)) }
        #expect(store.customColors.count == 8)
        #expect(store.customColors.first == "#000009")
        store.rememberColor("#000005")
        #expect(store.customColors.first == "#000005")
        #expect(store.customColors.filter { $0 == "#000005" }.count == 1)
    }

    @Test func totalsGroupByColorAndFilterByStartDate() {
        let (store, _, _, _) = make()
        store.save(ev("a", "2026-10-19", color: "#111111", allDay: false, st: "09:00", et: "18:00"))
        store.save(ev("b", "2026-10-20", color: "#111111", allDay: false, st: "10:00", et: "14:00"))
        store.save(ev("c", "2026-10-21", color: "#222222", allDay: false, st: "07:00", et: "15:00", wh: 7))
        store.save(ev("out", "2026-10-30", color: "#111111", allDay: false, st: "09:00", et: "18:00"))
        store.save(ev("allday", "2026-10-20", color: "#111111"))
        let t = store.totals(from: "2026-10-18", to: "2026-10-24")
        #expect(t.count == 2)
        #expect(t[0].color == "#111111")
        #expect(t[0].hours == 12)
        #expect(t[0].count == 2)
        #expect(t[1].color == "#222222")
        #expect(t[1].hours == 7)
    }

    @Test func importUpsertsByIdAndKeepsUnplaced() throws {
        let (store, _, _, _) = make()
        store.save(ev("a1", "2026-10-01"))
        let json = #"""
        [{"id":"a1","title":"早番","memo":"","color":"#06b6d4","startDate":"2026-10-20","endDate":"2026-10-20","placed":true,"allDay":false,"startTime":"07:00","endTime":"15:00","workHours":7.25,"_new":null},
         {"id":"s1","title":"夜勤","color":"#6366f1","startDate":null,"endDate":null,"placed":false,"allDay":false,"startTime":"22:00","endTime":"06:00","workHours":null}]
        """#
        let n = try store.importJSON(Data(json.utf8))
        #expect(n == 2)
        #expect(store.events.count == 2)
        #expect(store.events.first { $0.id == "a1" }?.title == "早番")
        #expect(store.events.first { $0.id == "s1" }?.placed == false)
        #expect(store.visibleEvents.map(\.id) == ["a1"])
    }

    @Test func importInvalidJSONThrowsAndLeavesEventsUntouched() {
        let (store, _, _, _) = make()
        store.save(ev("a", "2026-10-20"))
        #expect(throws: (any Error).self) { try store.importJSON(Data("not json".utf8)) }
        #expect(store.events.map(\.id) == ["a"])
    }

    @Test func corruptFileIsPreservedAndStoreStartsEmpty() throws {
        let name = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).json")
        try Data("not json".utf8).write(to: url)
        let store = Store(fileURL: url, defaults: UserDefaults(suiteName: name)!)
        #expect(store.events.isEmpty)
        store.save(ev("a", "2026-10-20"))
        let dir = url.deletingLastPathComponent().path
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        #expect(names.contains { $0.hasPrefix("\(url.deletingPathExtension().lastPathComponent).corrupt-") })
    }
}
