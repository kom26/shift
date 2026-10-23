import Foundation
import Testing
@testable import Shift

struct MonthGridTests {
    @Test func octoberSundayStart() {
        let g = Rules.monthGrid(year: 2026, month: 10, startMonday: false)
        #expect(g.count == 5)
        #expect(g[0][0] == "2026-09-27")
        #expect(g[0][4] == "2026-10-01")
        #expect(g[4][6] == "2026-10-31")
    }

    @Test func octoberMondayStart() {
        let g = Rules.monthGrid(year: 2026, month: 10, startMonday: true)
        #expect(g.count == 5)
        #expect(g[0][0] == "2026-09-28")
        #expect(g[4][6] == "2026-11-01")
    }

    @Test func februaryIsExactlyFourWeeks() {
        let g = Rules.monthGrid(year: 2026, month: 2, startMonday: false)
        #expect(g.count == 4)
        #expect(g[0][0] == "2026-02-01")
        #expect(g[3][6] == "2026-02-28")
    }

    @Test func rowCountMatchesMonthWeeksAndCellsAreDates() {
        for (y, m) in [(2026, 10), (2026, 2), (2026, 3), (2025, 6)] {
            for mon in [false, true] {
                let g = Rules.monthGrid(year: y, month: m, startMonday: mon)
                #expect(g.count == Rules.monthWeeks(year: y, month: m, startMonday: mon).count)
                for week in g {
                    #expect(week.count == 7)
                    for c in week { #expect(Rules.parse(c) != nil && c.count == 10) }
                }
            }
        }
    }

    @Test func isSameMonth() {
        #expect(Rules.isSameMonth("2026-10-31", as: "2026-10-01"))
        #expect(!Rules.isSameMonth("2026-11-01", as: "2026-10-15"))
    }
}
