import Foundation
import Testing
@testable import Shift

struct WorkplaceTests {
    private func make() -> Store {
        let name = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).json")
        return Store(fileURL: url, defaults: UserDefaults(suiteName: name)!)
    }

    private func evt(_ id: String, title: String, color: String) -> ShiftEvent {
        var e = ev(id, "2026-10-20", color: color)
        e.title = title
        return e
    }

    @Test func addTrimsName() {
        let store = make()
        store.addWorkplace(name: " ドンキ ", color: "#f59e0b")
        #expect(store.workplaces.count == 1)
        #expect(store.workplaces[0].name == "ドンキ")
        #expect(store.workplaces[0].color == "#f59e0b")
    }

    @Test func addIgnoresBlankName() {
        let store = make()
        store.addWorkplace(name: "   ", color: "#f59e0b")
        #expect(store.workplaces.isEmpty)
    }

    @Test func updateWithoutApplyKeepsEvents() {
        let store = make()
        store.addWorkplace(name: "ドンキ", color: "#f59e0b")
        store.save(evt("a", title: "ドンキ", color: "#f59e0b"))
        store.updateWorkplace(id: store.workplaces[0].id, name: "ドンキ新宿", color: "#10b981", applyToEvents: false)
        #expect(store.workplaces[0].name == "ドンキ新宿")
        #expect(store.workplaces[0].color == "#10b981")
        #expect(store.events[0].title == "ドンキ")
        #expect(store.events[0].color == "#f59e0b")
    }

    @Test func updateWithApplyChangesMatchingEventsOnly() {
        let store = make()
        store.addWorkplace(name: "ドンキ", color: "#f59e0b")
        store.save(evt("a", title: "ドンキ", color: "#111111"))
        store.save(evt("b", title: "ドンキ", color: "#222222"))
        store.save(evt("c", title: "まねき", color: "#333333"))
        store.updateWorkplace(id: store.workplaces[0].id, name: "ドンキ新宿", color: "#10b981", applyToEvents: true)
        #expect(store.events[0].title == "ドンキ新宿")
        #expect(store.events[0].color == "#10b981")
        #expect(store.events[1].title == "ドンキ新宿")
        #expect(store.events[1].color == "#10b981")
        #expect(store.events[2].title == "まねき")
        #expect(store.events[2].color == "#333333")
    }

    @Test func eventCountIsExactMatch() {
        let store = make()
        store.save(evt("a", title: "ドンキ", color: "#111111"))
        store.save(evt("b", title: "ドンキ", color: "#222222"))
        store.save(evt("c", title: "ドンキ新宿", color: "#333333"))
        #expect(store.eventCount(matchingTitle: "ドンキ") == 2)
    }

    @Test func deleteKeepsEvents() {
        let store = make()
        store.addWorkplace(name: "ドンキ", color: "#f59e0b")
        store.save(evt("a", title: "ドンキ", color: "#f59e0b"))
        store.deleteWorkplace(id: store.workplaces[0].id)
        #expect(store.workplaces.isEmpty)
        #expect(store.events.count == 1)
        #expect(store.events[0].title == "ドンキ")
    }

    @Test func moveReorders() {
        let store = make()
        store.addWorkplace(name: "A", color: "#111111")
        store.addWorkplace(name: "B", color: "#222222")
        store.addWorkplace(name: "C", color: "#333333")
        store.moveWorkplaces(from: IndexSet(integer: 0), to: 3)
        #expect(store.workplaces.map(\.name) == ["B", "C", "A"])
    }

    @Test func workplacesPersist() {
        let name = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).json")
        let defaults = UserDefaults(suiteName: name)!
        let store = Store(fileURL: url, defaults: defaults)
        store.addWorkplace(name: "ドンキ", color: "#f59e0b")
        let reloaded = Store(fileURL: url, defaults: defaults)
        #expect(reloaded.workplaces == store.workplaces)
        #expect(reloaded.workplaces.count == 1)
    }
}
