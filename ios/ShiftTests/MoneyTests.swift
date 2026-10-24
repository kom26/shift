import Testing
@testable import Shift

struct MoneyTests {
    @Test func roundsHalfAwayFromZero() { #expect(Money.yen(8812.5) == "¥8,813") }
    @Test func zero() { #expect(Money.yen(0) == "¥0") }
    @Test func grouping() { #expect(Money.yen(1234567) == "¥1,234,567") }
    @Test func roundsDown() { #expect(Money.yen(999.4) == "¥999") }
}
