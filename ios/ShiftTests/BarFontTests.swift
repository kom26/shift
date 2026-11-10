import Foundation
import Testing
@testable import Shift

struct BarFontTests {
    @Test func therAreFiveChoicesAndTheDefaultIsTheBundledRoundGothic() {
        #expect(BarFontChoice.allCases.count == 5)
        #expect(BarFontChoice.zen.name(for: .bold) == "ZenMaruGothic-Bold")
    }

    @Test func everyChoiceHasADistinctNameForBoldAndRegular() {
        for c in BarFontChoice.allCases {
            #expect(!c.name(for: .bold).isEmpty && !c.name(for: .regular).isEmpty)
        }
        #expect(BarFontChoice.gothic.name(for: .bold) != BarFontChoice.gothic.name(for: .regular))
        #expect(Set(BarFontChoice.allCases.map { $0.name(for: .bold) }).count == 5)
    }

    @Test func theThinnestBarIsTwoPointsAboveTheText() {
        #expect(BarFontSize.minBar(font: 7.6) == 10)
        #expect(BarFontSize.minBar(font: 10) == 12)
    }

    @Test func titleSizeStartsFromTheOldSingleValueOnce() {
        let name = UUID().uuidString
        let d = UserDefaults(suiteName: name)!
        d.set(1.5, forKey: BarFontSize.monthKey)
        d.set(-1.0, forKey: BarFontSize.weekKey)
        BarFontSize.migrate(defaults: d)
        #expect(d.double(forKey: BarFontSize.monthTitleKey) == 1.5)
        #expect(d.double(forKey: BarFontSize.weekTitleKey) == -1.0)
        // 2 回目以降は、変えない
        d.set(2.0, forKey: BarFontSize.monthKey)
        BarFontSize.migrate(defaults: d)
        #expect(d.double(forKey: BarFontSize.monthTitleKey) == 1.5)
    }
}
