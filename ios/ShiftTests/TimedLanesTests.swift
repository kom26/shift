import Foundation
import Testing
@testable import Shift

struct TimedLanesTests {
    private func item(_ id: String, _ top: Double, _ bottom: Double) -> TimedLanes.Item {
        TimedLanes.Item(id: id, top: top, bottom: bottom)
    }

    @Test func nonOverlappingStayFullWidth() {
        let r = TimedLanes.assign([item("a", 0.1, 0.2), item("b", 0.3, 0.4)])
        #expect(r["a"] == TimedLanes.Slot(lane: 0, count: 1))
        #expect(r["b"] == TimedLanes.Slot(lane: 0, count: 1))
    }

    @Test func overlappingSplitSideBySide() {
        let r = TimedLanes.assign([item("a", 0.1, 0.3), item("b", 0.2, 0.4)])
        #expect(r["a"] == TimedLanes.Slot(lane: 0, count: 2))
        #expect(r["b"] == TimedLanes.Slot(lane: 1, count: 2))
    }

    @Test func laterEventReusesFreeLaneInSameCluster() {
        // a が長く、b と c はその間に順に入る(c は b の列を使い回す)
        let r = TimedLanes.assign([item("a", 0.1, 0.6), item("b", 0.1, 0.3), item("c", 0.35, 0.5)])
        #expect(r["a"]?.count == 2)
        #expect(r["b"]?.lane == 1)
        #expect(r["c"]?.lane == 1)
        #expect(r["c"]?.count == 2)
    }

    @Test func separateClustersAreIndependent() {
        let r = TimedLanes.assign([item("a", 0.1, 0.3), item("b", 0.2, 0.4), item("c", 0.5, 0.6)])
        #expect(r["c"] == TimedLanes.Slot(lane: 0, count: 1))
    }
}
