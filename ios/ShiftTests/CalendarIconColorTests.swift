import Testing
@testable import Shift

struct CalendarIconColorTests {
    @Test func splitAndJoinKeepTheColor() {
        let icon = CalendarIcon.join(name: "briefcase.fill", color: "#3b82f6")
        #expect(icon == "briefcase.fill|#3b82f6")
        let (name, color) = CalendarIcon.split(icon)
        #expect(name == "briefcase.fill")
        #expect(color == "#3b82f6")
    }

    @Test func iconWithoutColorHasNoColor() {
        let (name, color) = CalendarIcon.split("house.fill")
        #expect(name == "house.fill")
        #expect(color == nil)
        #expect(CalendarIcon.join(name: "house.fill", color: nil) == "house.fill")
    }

    @Test func resolvedKeepsColorAndFallsBackOnUnknownName() {
        #expect(CalendarIcon.resolved("star.fill|#f28d8d") == "star.fill|#f28d8d")
        #expect(CalendarIcon.resolved("unknown.symbol|#f28d8d") == CalendarIcon.defaultName + "|#f28d8d")
        #expect(CalendarIcon.resolved("unknown.symbol") == CalendarIcon.defaultName)
    }

    @Test func brokenColorIsIgnored() {
        #expect(CalendarIcon.split("star.fill|red").color == nil)
    }
}
