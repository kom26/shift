import Foundation
import Testing
@testable import Shift

struct LabelTests {
    private func make() -> (store: Store, url: URL, defaults: UserDefaults) {
        let name = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).json")
        let defaults = UserDefaults(suiteName: name)!
        return (Store(fileURL: url, defaults: defaults), url, defaults)
    }

    private func labeled(_ id: String, _ labelId: String?) -> ShiftEvent {
        var e = ev(id, "2026-10-20")
        e.labelId = labelId
        return e
    }

    private func work(_ id: String, _ workplaceId: String) -> ShiftEvent {
        var e = ev(id, "2026-10-20")
        e.workplaceId = workplaceId
        return e
    }

    @Test func grayIsFirstInThePalette() {
        #expect(Store.defaultColors[0] == EventLabel.noneColor)
        #expect(Store.defaultColors[0] == "#bec1cc")
    }

    @Test func oldEventJSONDecodesAndNewFieldsAreOptional() throws {
        let old = ##"{"id":"a","title":"t","memo":"","color":"#fff","placed":true,"allDay":true}"##
        let e = try JSONDecoder().decode(ShiftEvent.self, from: Data(old.utf8))
        #expect(e.labelId == nil)
        #expect(e.ownColor == nil)
        let json = String(data: try JSONEncoder().encode(e), encoding: .utf8) ?? ""
        #expect(!json.contains("labelId"))
        #expect(!json.contains("layerIds"))
    }

    @Test func legacyLayerBecomesTheFirstRealLabelOfANormalEvent() throws {
        let json = ##"{"id":"a","title":"t","memo":"","color":"#fff","placed":true,"allDay":true,"layerIds":["mine","x","y"]}"##
        #expect(try JSONDecoder().decode(ShiftEvent.self, from: Data(json.utf8)).labelId == "x")
        let onlyMine = ##"{"id":"a","title":"t","memo":"","color":"#fff","placed":true,"allDay":true,"layerIds":["mine"]}"##
        #expect(try JSONDecoder().decode(ShiftEvent.self, from: Data(onlyMine.utf8)).labelId == nil)
    }

    @Test func legacyLayerIsDroppedFromAWorkEvent() throws {
        let json = ##"{"id":"a","title":"t","memo":"","color":"#fff","placed":true,"allDay":true,"workplaceId":"w1","layerIds":["x"]}"##
        #expect(try JSONDecoder().decode(ShiftEvent.self, from: Data(json.utf8)).labelId == nil)
    }

    @Test func labelAndOwnColorSurviveEncoding() throws {
        var e = labeled("a", "x")
        e.ownColor = true
        let back = try JSONDecoder().decode(ShiftEvent.self, from: JSONEncoder().encode(e))
        #expect(back.labelId == "x")
        #expect(back.ownColor == true)
    }

    @Test func groupFilterShowsOnlyThatGroup() {
        let (store, _, _) = make()
        store.addWorkplace(Workplace(id: "w1", name: "ドンキ", color: "#ef4444"))
        let date = store.addLabel(name: "デート", color: "#111111")!
        store.save(work("work", "w1"))
        store.save(labeled("date", date.id))
        store.save(labeled("plain", nil))
        #expect(store.visibleEvents.count == 3)
        store.setWorkplaceGroup(true)
        #expect(store.visibleEvents.map(\.id) == ["work"])
        store.clearFilters()
        store.setLabelGroup(true)
        #expect(Set(store.visibleEvents.map(\.id)) == ["date", "plain"])
        store.toggleLabelFilter(Store.noLabelKey)
        #expect(store.visibleEvents.map(\.id) == ["date"])
    }

    @Test func selectingBothGroupsShowsEverything() {
        let (store, _, _) = make()
        store.addWorkplace(Workplace(id: "w1", name: "ドンキ", color: "#ef4444"))
        let date = store.addLabel(name: "デート", color: "#111111")!
        store.save(work("work", "w1"))
        store.save(labeled("date", date.id))
        store.setWorkplaceGroup(true)
        store.setLabelGroup(true)
        #expect(store.visibleEvents.count == 2)
    }

    @Test func placingAnEventHiddenByTheFilterClearsIt() {
        let (store, _, _) = make()
        let date = store.addLabel(name: "デート", color: "#111111")!
        store.toggleLabelFilter(date.id)
        store.save(labeled("plain", nil))
        #expect(!store.isFiltering)
        #expect(store.visibleEvents.map(\.id) == ["plain"])
    }

    @Test func deletingALabelKeepsEventsAndReturnsThemToNone() {
        let (store, _, _) = make()
        let date = store.addLabel(name: "デート", color: "#111111")!
        var e = labeled("e", date.id)
        e.color = date.color
        e.ownColor = false
        store.save(e)
        store.toggleLabelFilter(date.id)
        store.deleteLabel(id: date.id)
        #expect(store.labels.isEmpty)
        #expect(store.events.first?.labelId == nil)
        #expect(store.events.first?.color == EventLabel.noneColor)
        #expect(store.checkedLabels.isEmpty)
    }

    @Test func deletingALabelKeepsAnOwnColor() {
        let (store, _, _) = make()
        let date = store.addLabel(name: "デート", color: "#111111")!
        var e = labeled("e", date.id)
        e.color = "#abcdef"
        e.ownColor = true
        store.save(e)
        store.deleteLabel(id: date.id)
        #expect(store.events.first?.color == "#abcdef")
    }

    @Test func labelColorChangeFollowsOnlyEventsWithoutOwnColor() {
        let (store, _, _) = make()
        let date = store.addLabel(name: "デート", color: "#111111")!
        var follows = labeled("follows", date.id)
        follows.color = "#111111"
        follows.ownColor = false
        var own = labeled("own", date.id)
        own.color = "#abcdef"
        own.ownColor = true
        var legacy = labeled("legacy", date.id)
        legacy.color = "#111111"
        var legacyCustom = labeled("legacyCustom", date.id)
        legacyCustom.color = "#999999"
        [follows, own, legacy, legacyCustom].forEach(store.save)
        store.updateLabel(id: date.id, name: "デート", color: "#222222")
        func color(_ id: String) -> String? { store.events.first { $0.id == id }?.color }
        #expect(color("follows") == "#222222")
        #expect(color("own") == "#abcdef")
        #expect(color("legacy") == "#222222")
        #expect(color("legacyCustom") == "#999999")
    }

    @Test func workplaceColorChangeFollowsEventsWithoutOwnColor() {
        let (store, _, _) = make()
        store.addWorkplace(Workplace(id: "w1", name: "ドンキ", color: "#ef4444"))
        var follows = work("follows", "w1")
        follows.color = "#ef4444"
        follows.ownColor = false
        var own = work("own", "w1")
        own.color = "#abcdef"
        own.ownColor = true
        store.save(follows)
        store.save(own)
        store.updateWorkplace(id: "w1", name: "ドンキ", color: "#3b82f6", applyToEvents: false)
        #expect(store.events.first { $0.id == "follows" }?.color == "#3b82f6")
        #expect(store.events.first { $0.id == "own" }?.color == "#abcdef")
    }

    @Test func groupColorPrefersWorkplaceThenLabelThenGray() {
        let (store, _, _) = make()
        store.addWorkplace(Workplace(id: "w1", name: "ドンキ", color: "#ef4444"))
        let date = store.addLabel(name: "デート", color: "#111111")!
        #expect(store.groupColor(workplaceId: "w1", labelId: nil) == "#ef4444")
        #expect(store.groupColor(workplaceId: nil, labelId: date.id) == "#111111")
        #expect(store.groupColor(workplaceId: nil, labelId: nil) == EventLabel.noneColor)
        #expect(store.groupColor(workplaceId: nil, labelId: "missing") == EventLabel.noneColor)
    }

    @Test func labelsKeepTheirOrderWhenMoved() {
        let (store, _, _) = make()
        let a = store.addLabel(name: "A", color: "#111111")!
        let b = store.addLabel(name: "B", color: "#222222")!
        let c = store.addLabel(name: "C", color: "#333333")!
        store.moveLabels(from: IndexSet(integer: 2), to: 0)
        #expect(store.labels.map(\.id) == [c.id, a.id, b.id])
    }

    @Test func labelsAndFilterPersistAndLegacyLayersAreRead() {
        let (store, url, defaults) = make()
        let l = store.addLabel(name: "  デート ", color: "#111111")!
        store.toggleLabelFilter(l.id)
        let reloaded = Store(fileURL: url, defaults: defaults)
        #expect(reloaded.labels == [EventLabel(id: l.id, name: "デート", color: "#111111")])
        #expect(reloaded.checkedLabels == [l.id])

        let legacy = UserDefaults(suiteName: UUID().uuidString)!
        legacy.set(try? JSONEncoder().encode([EventLabel(id: "old", name: "サークル", color: "#222222")]), forKey: "shift-layers")
        #expect(Store(fileURL: url, defaults: legacy).labels.map(\.id) == ["old"])
    }

    @Test func blankLabelNameIsRejected() {
        let (store, _, _) = make()
        #expect(store.addLabel(name: "  ", color: "#111111") == nil)
        #expect(store.labels.isEmpty)
    }

    @Test func labelEventCountIgnoresWorkEvents() {
        let (store, _, _) = make()
        store.addWorkplace(Workplace(id: "w1", name: "ドンキ", color: "#ef4444"))
        let date = store.addLabel(name: "デート", color: "#111111")!
        store.save(labeled("a", date.id))
        store.save(labeled("b", nil))
        store.save(work("w", "w1"))
        #expect(store.labelEventCount(date.id) == 1)
        #expect(store.labelEventCount(nil) == 1)
    }
}
