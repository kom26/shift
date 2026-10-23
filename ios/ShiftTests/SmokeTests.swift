import Testing
@testable import Shift

struct SmokeTests {
    @Test func testTargetRuns() {
        #expect(1 + 1 == 2)
    }
}
