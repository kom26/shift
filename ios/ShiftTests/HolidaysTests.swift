import Foundation
import Testing
@testable import Shift

struct HolidaysTests {
    @Test func builtinTableHasKnownEntries() {
        #expect(BuiltinHolidays.table.count == 68)
        #expect(BuiltinHolidays.table["2026-01-01"] == "元日")
    }

    @Test func nameLooksUpBuiltin() {
        let h = Holidays(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(h.name(on: "2026-01-01") == "元日")
        #expect(h.name(on: "2026-10-21") == nil)
    }

    @Test func cachedEntriesAreMergedOnInit() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(try JSONEncoder().encode(["2030-01-01": "元日"]), forKey: "shift-holidays")
        let h = Holidays(defaults: defaults)
        #expect(h.name(on: "2030-01-01") == "元日")
        #expect(h.name(on: "2026-01-01") == "元日")
    }
}
