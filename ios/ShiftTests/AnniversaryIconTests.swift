import Testing
@testable import Shift

struct AnniversaryIconTests {
    @Test func everyIconHasADistinctWidgetSymbol() {
        let names = Anniversary.Icon.allCases.map(\.symbolName)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
    }
}
