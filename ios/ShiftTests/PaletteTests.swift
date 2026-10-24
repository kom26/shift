import Foundation
import Testing
@testable import Shift

struct PaletteTests {
    @Test func defaultPaletteShape() {
        let colors = Store.defaultColors
        #expect(colors.count == 8)
        #expect(Set(colors).count == colors.count)
        let hexDigits = Set("0123456789abcdef")
        for c in colors {
            #expect(c.count == 7)
            #expect(c.first == "#")
            #expect(c.dropFirst().allSatisfy { hexDigits.contains($0) })
        }
        #expect(colors[0] == "#b9a6f2")
    }

    @Test func newEventsUseFirstColor() {
        #expect(ShiftEvent.newUnplaced().color == Store.defaultColors[0])
        #expect(ShiftEvent.new(on: "2026-10-01").color == Store.defaultColors[0])
    }
}
