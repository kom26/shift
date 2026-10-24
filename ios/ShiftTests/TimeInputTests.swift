import Foundation
import Testing
@testable import Shift

struct TimeInputTests {
    @Test func parseValid() {
        #expect(Rules.parseTimeDigits("0930", maxMinutes: 1620) == "09:30")
        #expect(Rules.parseTimeDigits("2700", maxMinutes: 1620) == "27:00")
        #expect(Rules.parseTimeDigits("3600", maxMinutes: 2160) == "36:00")
        #expect(Rules.parseTimeDigits("09:30", maxMinutes: 1620) == "09:30")
    }

    @Test func parseInvalid() {
        #expect(Rules.parseTimeDigits("2701", maxMinutes: 1620) == nil)
        #expect(Rules.parseTimeDigits("3601", maxMinutes: 2160) == nil)
        #expect(Rules.parseTimeDigits("2575", maxMinutes: 1620) == nil)
        #expect(Rules.parseTimeDigits("930", maxMinutes: 1620) == nil)
        #expect(Rules.parseTimeDigits("12345", maxMinutes: 1620) == nil)
        #expect(Rules.parseTimeDigits("", maxMinutes: 1620) == nil)
        #expect(Rules.parseTimeDigits("abcd", maxMinutes: 1620) == nil)
    }

    @Test func wheelOptions() {
        #expect(Rules.hourOptions(maxHour: 27).count == 28)
        #expect(Rules.minuteOptions.count == 12)
        #expect(Rules.minuteOptions.first == 0)
        #expect(Rules.minuteOptions.last == 55)
    }
}
