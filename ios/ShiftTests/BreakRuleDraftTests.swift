import Testing
@testable import Shift

struct BreakRuleDraftTests {
    @Test func emptyFieldsCountAsZeroAndNoopRowsAreDropped() {
        let rules = BreakRuleDraft.clean([("", "45"), ("6", ""), ("8", "60"), ("", "")], comparison: .over)
        #expect(rules.count == 3)
        #expect(rules[0].hours == 0)
        #expect(rules[0].minutes == 45)
        #expect(rules[0].comparison == .over)
        #expect(rules[1].hours == 6)
        #expect(rules[1].minutes == 0)
        #expect(rules[2].hours == 8)
        #expect(rules[2].minutes == 60)
    }

    @Test func allZeroRowsAreDropped() {
        #expect(BreakRuleDraft.clean([("", ""), ("0", "0")], comparison: .over).isEmpty)
    }
}
