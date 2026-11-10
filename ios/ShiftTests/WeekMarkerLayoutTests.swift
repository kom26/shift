import Testing
@testable import Shift

struct WeekMarkerLayoutTests {
    private typealias L = WeekMarkerLayout
    private func item(_ k: L.Kind, _ h: Int, _ m: Int) -> L.Item { .init(kind: k, minutes: h * 60 + m, color: k == .bell ? nil : "#df3226") }

    @Test func farApartMarkersAreNotSplit() {
        let s = L.layout([item(.bell, 16, 30), item(.start, 17, 45), item(.due, 19, 0)])
        #expect(s.count == 3 && s.allSatisfy { $0.count == 1 && $0.slot == 0 && $0.extra == 0 })
    }

    @Test func nearMarkersSplitInOrderBellStartDue() {
        let s = L.layout([item(.due, 17, 20), item(.bell, 17, 0), item(.start, 17, 10)])
        #expect(s.map(\.kind) == [.bell, .start, .due])
        #expect(s.map(\.slot) == [0, 1, 2] && s.allSatisfy { $0.count == 3 })
    }

    @Test func exactlyThirtyMinutesIsNearAndThirtyOneIsNot() {
        #expect(L.layout([item(.bell, 17, 0), item(.due, 17, 30)]).allSatisfy { $0.count == 2 })
        #expect(L.layout([item(.bell, 17, 0), item(.due, 17, 31)]).allSatisfy { $0.count == 1 })
    }

    @Test func chainedNeighboursFormOneGroup() {
        let s = L.layout([item(.bell, 17, 0), item(.start, 17, 25), item(.due, 17, 50)])
        #expect(s.allSatisfy { $0.count == 3 })
    }

    @Test func sameKindIsMergedWithAPlusCount() {
        let s = L.layout([item(.bell, 17, 0), item(.bell, 17, 0), item(.start, 17, 10)])
        #expect(s.count == 2)
        #expect(s.first { $0.kind == .bell }?.extra == 1)
        #expect(s.allSatisfy { $0.count == 2 })
    }

    @Test func sixAtTheSameTimeSplitInThreeWithPlusOneEach() {
        let s = L.layout([item(.bell, 17, 0), item(.bell, 17, 0), item(.start, 17, 0), item(.start, 17, 0),
                          item(.due, 17, 0), item(.due, 17, 0)])
        #expect(s.count == 3 && s.allSatisfy { $0.count == 3 && $0.extra == 1 })
    }
}
