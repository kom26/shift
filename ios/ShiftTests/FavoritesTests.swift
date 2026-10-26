import Foundation
import Testing
@testable import Shift

struct FavoritesTests {
    private func make() -> (store: Store, url: URL, defaults: UserDefaults) {
        let name = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).json")
        let defaults = UserDefaults(suiteName: name)!
        return (Store(fileURL: url, defaults: defaults), url, defaults)
    }

    private func timed(_ id: String, _ date: String, title: String = "居酒屋") -> ShiftEvent {
        var e = ShiftEvent.new(on: date)
        e.id = id
        e.title = title
        e.startTime = "18:00"
        e.endTime = "24:00"
        e.allDay = false
        return e
    }

    @Test func addFromEventStripsDatesAndDeduplicates() {
        let (store, _, _) = make()
        let e = timed("a", "2026-10-20")
        #expect(store.addFavorite(from: e))
        #expect(!store.addFavorite(from: timed("b", "2026-10-21")))
        #expect(store.favorites.count == 1)
        #expect(store.favorites[0].startDate == nil)
        #expect(!store.favorites[0].placed)
        #expect(store.favorites[0].id != "a")
    }

    @Test func favoritesPersistAcrossInstances() {
        let (store, url, defaults) = make()
        store.addFavorite(from: timed("a", "2026-10-20"))
        let reloaded = Store(fileURL: url, defaults: defaults)
        #expect(reloaded.favorites.map { $0.title } == ["居酒屋"])
    }

    @Test func stampToggleAddsThenRemoves() {
        let (store, _, _) = make()
        store.addFavorite(from: timed("a", "2026-10-20"))
        let fid = store.favorites[0].id
        #expect(store.stampToggle(favoriteId: fid, on: "2026-10-22") == .placed)
        #expect(store.events.count == 1)
        #expect(store.events[0].startDate == "2026-10-22")
        #expect(store.events[0].placed)
        #expect(store.stampToggle(favoriteId: fid, on: "2026-10-22") == .removed)
        #expect(store.events.isEmpty)
    }

    @Test func stampCopyAlwaysAdds() {
        let (store, _, _) = make()
        store.addFavorite(from: timed("a", "2026-10-20"))
        let fid = store.favorites[0].id
        store.stampCopy(favoriteId: fid, on: "2026-10-22")
        store.stampCopy(favoriteId: fid, on: "2026-10-22")
        #expect(store.events.count == 2)
    }

    @Test func dropPreviewResolvesFavoriteIds() {
        let (store, _, _) = make()
        store.addFavorite(from: timed("a", "2026-10-20"))
        let fid = store.favorites[0].id
        let p = store.dropPreview(id: Store.favoritePrefix + fid, on: "2026-10-23")
        #expect(p?.startDate == "2026-10-23")
    }

    @Test func suggestionsNeedThreeAndSkipRegisteredOrHidden() {
        let (store, _, _) = make()
        store.save(timed("1", "2026-10-01"))
        store.save(timed("2", "2026-10-02"))
        #expect(store.favoriteSuggestions().isEmpty)
        store.save(timed("3", "2026-10-03"))
        #expect(store.favoriteSuggestions().count == 1)
        store.hideSuggestion(store.favoriteSuggestions()[0])
        #expect(store.favoriteSuggestions().isEmpty)
    }

    @Test func removeAndMoveToFront() {
        let (store, _, _) = make()
        store.addFavorite(from: timed("a", "2026-10-20", title: "A"))
        store.addFavorite(from: timed("b", "2026-10-20", title: "B"))
        store.moveFavoriteToFront(id: store.favorites[1].id)
        #expect(store.favorites.map { $0.title } == ["B", "A"])
        store.removeFavorite(id: store.favorites[0].id)
        #expect(store.favorites.map { $0.title } == ["A"])
    }
}
