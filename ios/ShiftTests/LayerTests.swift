import Foundation
import Testing
@testable import Shift

struct LayerTests {
    private func make() -> (store: Store, url: URL, defaults: UserDefaults) {
        let name = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).json")
        let defaults = UserDefaults(suiteName: name)!
        return (Store(fileURL: url, defaults: defaults), url, defaults)
    }

    private func layered(_ id: String, _ ids: [String]?) -> ShiftEvent {
        var e = ev(id, "2026-10-20")
        e.layerIds = ids
        return e
    }

    @Test func eventWithoutLayerBelongsToMine() {
        #expect(ev("a", "2026-10-20").effectiveLayerIds == [Layer.mineId])
        #expect(layered("a", []).effectiveLayerIds == [Layer.mineId])
        #expect(layered("a", ["x", "y"]).effectiveLayerIds == ["x", "y"])
    }

    @Test func oldEventJSONDecodesAndLayerlessEventsAreEncodedUnchanged() throws {
        let old = #"{"id":"a","title":"t","memo":"","color":"#fff","placed":true,"allDay":true}"#
        let e = try JSONDecoder().decode(ShiftEvent.self, from: Data(old.utf8))
        #expect(e.layerIds == nil)
        let json = String(data: try JSONEncoder().encode(e), encoding: .utf8) ?? ""
        #expect(!json.contains("layerIds"))
    }

    @Test func layerIdsSurviveEncoding() throws {
        let e = layered("a", ["x"])
        let back = try JSONDecoder().decode(ShiftEvent.self, from: JSONEncoder().encode(e))
        #expect(back.layerIds == ["x"])
    }

    @Test func layerFilterShowsEventsInAnyCheckedLayer() {
        let (store, _, _) = make()
        let circle = store.addLayer(name: "サークル", color: "#111111")!
        let trip = store.addLayer(name: "旅行", color: "#222222")!
        store.save(layered("mine", nil))
        store.save(layered("circle", [circle.id]))
        store.save(layered("both", [Layer.mineId, trip.id]))
        #expect(store.visibleEvents.count == 3)
        store.toggleLayerFilter(circle.id)
        #expect(store.visibleEvents.map(\.id) == ["circle"])
        store.toggleLayerFilter(Layer.mineId)
        #expect(store.visibleEvents.map(\.id) == ["mine", "circle", "both"])
        store.clearFilters()
        #expect(store.visibleEvents.count == 3)
        #expect(!store.isFiltering)
    }

    @Test func workplaceAndLayerFiltersBothApply() {
        let (store, _, _) = make()
        store.addWorkplace(Workplace(id: "w1", name: "A", color: "#ef4444"))
        let circle = store.addLayer(name: "サークル", color: "#111111")!
        var a = layered("a", [Layer.mineId, circle.id]); a.workplaceId = "w1"
        var b = layered("b", [circle.id])
        b.workplaceId = nil
        store.save(a)
        store.save(b)
        store.toggleWorkplaceFilter("w1")
        store.toggleLayerFilter(circle.id)
        #expect(store.visibleEvents.map(\.id) == ["a"])
    }

    @Test func placingAnEventHiddenByLayerFilterClearsThatFilter() {
        let (store, _, _) = make()
        let circle = store.addLayer(name: "サークル", color: "#111111")!
        store.toggleLayerFilter(circle.id)
        store.save(layered("mine", nil))
        #expect(store.checkedLayers.isEmpty)
        #expect(store.visibleEvents.map(\.id) == ["mine"])
    }

    @Test func deletingALayerKeepsEventsAndReturnsThemToMine() {
        let (store, _, _) = make()
        let circle = store.addLayer(name: "サークル", color: "#111111")!
        let trip = store.addLayer(name: "旅行", color: "#222222")!
        store.save(layered("only", [circle.id]))
        store.save(layered("two", [circle.id, trip.id]))
        store.toggleLayerFilter(circle.id)
        store.deleteLayer(id: circle.id)
        #expect(store.layers.map(\.id) == [trip.id])
        #expect(store.events.first { $0.id == "only" }?.effectiveLayerIds == [Layer.mineId])
        #expect(store.events.first { $0.id == "two" }?.layerIds == [trip.id])
        #expect(store.checkedLayers.isEmpty)
    }

    @Test func layersAndFilterPersist() {
        let (store, url, defaults) = make()
        let l = store.addLayer(name: "  サークル ", color: "#111111")!
        store.toggleLayerFilter(l.id)
        let reloaded = Store(fileURL: url, defaults: defaults)
        #expect(reloaded.layers == [Layer(id: l.id, name: "サークル", color: "#111111")])
        #expect(reloaded.checkedLayers == [l.id])
        #expect(reloaded.allLayers.first?.id == Layer.mineId)
    }

    @Test func blankLayerNameIsRejected() {
        let (store, _, _) = make()
        #expect(store.addLayer(name: "  ", color: "#111111") == nil)
        #expect(store.layers.isEmpty)
    }
}
