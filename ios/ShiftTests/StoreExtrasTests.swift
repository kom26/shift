import Foundation
import Testing
@testable import Shift

struct StoreExtrasTests {
    private func make() -> Store {
        let name = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).json")
        return Store(fileURL: url, defaults: UserDefaults(suiteName: name)!)
    }

    @Test func duplicatePlacedGoesAfterLastPlaced() {
        let store = make()
        store.save(ev("a", "2026-10-05"))
        store.save(ev("u", nil, placed: false))
        store.save(ev("b", "2026-10-06"))
        store.duplicate(id: "a")
        #expect(store.events.count == 4)
        #expect(store.events[0].id == "a")
        #expect(store.events[1].id == "b")
        #expect(store.events[3].id == "u")
        let copy = store.events[2]
        #expect(copy.id != "a" && copy.id != "b" && copy.id != "u")
        #expect(copy.startDate == "2026-10-05")
        #expect(copy.title == "a")
        #expect(copy.placed)
    }

    @Test func duplicateUnplacedGoesToEnd() {
        let store = make()
        store.save(ev("a", "2026-10-05"))
        store.save(ev("u", nil, placed: false))
        store.save(ev("v", nil, placed: false))
        store.duplicate(id: "u")
        #expect(store.events.count == 4)
        #expect(Array(store.events.map(\.id).prefix(3)) == ["a", "u", "v"])
        #expect(store.events[3].id != "u")
        #expect(store.events[3].title == "u")
        #expect(!store.events[3].placed)
    }

    @Test func duplicateUnknownIdIsIgnored() {
        let store = make()
        store.save(ev("a", "2026-10-05"))
        store.duplicate(id: "nope")
        #expect(store.events.map(\.id) == ["a"])
    }
}
