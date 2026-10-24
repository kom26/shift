import Testing
@testable import Shift

struct BreakRuleDraftTests {
    @Test func dropsEmptyHoursAndDefaultsMinutes() {
        let rules = BreakRuleDraft.clean([("", "45"), ("6", ""), ("8", "60")], comparison: .over)
        #expect(rules.count == 2)
        #expect(rules[0].hours == 6)
        #expect(rules[0].minutes == 0)
        #expect(rules[0].comparison == .over)
        #expect(rules[1].hours == 8)
        #expect(rules[1].minutes == 60)
    }
}
