import Testing
@testable import Shift

struct BreakRulesTests {
    private let rules = [
        BreakRule(id: "a", hours: 6, comparison: .atLeast, minutes: 30),
        BreakRule(id: "b", hours: 8, comparison: .over, minutes: 90),
    ]

    @Test func customRules() {
        #expect(BreakRules.minutes(span: 360, rules: rules) == 30)
        #expect(BreakRules.minutes(span: 361, rules: rules) == 30)
        #expect(BreakRules.minutes(span: 480, rules: rules) == 30)
        #expect(BreakRules.minutes(span: 481, rules: rules) == 90)
        #expect(BreakRules.minutes(span: 359, rules: rules) == 0)
    }

    @Test func statutoryWhenEmpty() {
        #expect(BreakRules.minutes(span: 480, rules: []) == 45)
        #expect(BreakRules.minutes(span: 481, rules: []) == 60)
        #expect(BreakRules.minutes(span: 360, rules: []) == 0)
        #expect(BreakRules.minutes(span: 361, rules: []) == 45)
    }

    @Test func sameThresholdUsesLater() {
        let r = [
            BreakRule(id: "a", hours: 6, comparison: .atLeast, minutes: 30),
            BreakRule(id: "b", hours: 6, comparison: .over, minutes: 50),
        ]
        #expect(BreakRules.minutes(span: 361, rules: r) == 50)
        #expect(BreakRules.minutes(span: 360, rules: r) == 30)
    }
}
