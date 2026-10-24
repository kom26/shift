import Foundation
import Testing
@testable import Shift

struct TimeInputTests {
    @Test func parseValid() {
        #expect(Rules.parseTimeDigits("0930", allow24: false) == "09:30")
        #expect(Rules.parseTimeDigits("09:30", allow24: false) == "09:30")
        #expect(Rules.parseTimeDigits("2359", allow24: false) == "23:59")
        #expect(Rules.parseTimeDigits("0000", allow24: false) == "00:00")
        #expect(Rules.parseTimeDigits("2400", allow24: true) == "24:00")
    }

    @Test func parseInvalid() {
        #expect(Rules.parseTimeDigits("2400", allow24: false) == nil)
        #expect(Rules.parseTimeDigits("2575", allow24: false) == nil)
        #expect(Rules.parseTimeDigits("930", allow24: false) == nil)
        #expect(Rules.parseTimeDigits("12345", allow24: false) == nil)
        #expect(Rules.parseTimeDigits("", allow24: false) == nil)
        #expect(Rules.parseTimeDigits("abcd", allow24: false) == nil)
    }

    @Test func options15() {
        let a = Rules.timeOptions15(allow24: false)
        #expect(a.count == 96)
        #expect(a.first == "00:00")
        #expect(a.last == "23:45")
        #expect(a.contains("09:15"))
        #expect(!a.contains("09:10"))
        let b = Rules.timeOptions15(allow24: true)
        #expect(b.count == 97)
        #expect(b.last == "24:00")
    }
}
