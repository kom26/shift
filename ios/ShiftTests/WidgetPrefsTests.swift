import Foundation
import Testing
@testable import Shift

struct WidgetPrefsTests {
    @Test func olderDataWithMissingFieldsFallsBackToDefaults() throws {
        let json = #"{"calendarId":"abc","showAlarms":false}"#
        let p = try JSONDecoder().decode(WidgetPrefs.self, from: Data(json.utf8))
        #expect(p.calendarId == "abc")
        #expect(p.showAlarms == false)
        #expect(p.showBirthdays && p.showAnniversaries && p.showPayday && p.showHours && p.showEstimatedPay)
        #expect(p.workplaceIds.isEmpty && p.labelIds.isEmpty)
    }

    @Test func olderDataBecomesSingleCalendarList() throws {
        let own = try JSONDecoder().decode(WidgetPrefs.self, from: Data(#"{"showAlarms":true}"#.utf8))
        #expect(own.calendarIds == [""] && own.calendarId == nil && !own.canSwitch)
        let shared = try JSONDecoder().decode(WidgetPrefs.self, from: Data(#"{"calendarId":"abc"}"#.utf8))
        #expect(shared.calendarIds == ["abc"] && shared.sharedCalendarIds == ["abc"])
    }

    @Test func viewingCyclesThroughCalendarsInChosenOrder() {
        var p = WidgetPrefs()
        p.setCalendars(["", "job", "fam"])
        #expect(p.canSwitch && p.calendarId == nil)
        #expect(p.viewing(0).calendarId == nil)
        #expect(p.viewing(1).calendarId == "job")
        #expect(p.viewing(2).calendarId == "fam")
        #expect(p.viewing(3).calendarId == nil)  // 1 周したら最初へ
        #expect(p.viewing(-1).calendarId == "fam")
        #expect(p.sharedCalendarIds == ["job", "fam"])
        p.setCalendars([])  // 空にはならず、自分のカレンダーだけ
        #expect(p.calendarIds == [""] && !p.canSwitch)
    }

    @Test func calendarCursorAdvancesAndWraps() {
        let defaults = UserDefaults(suiteName: "widget-cursor-" + UUID().uuidString)!
        let cursor = WidgetCalendarCursor(size: "small", defaults: defaults)
        #expect(cursor.index == 0)
        cursor.advance(count: 3)
        cursor.advance(count: 3)
        #expect(cursor.index == 2)
        cursor.advance(count: 3)
        #expect(cursor.index == 0)
        cursor.advance(count: 3)
        cursor.advance(count: 2)  // カレンダーが減っても、範囲の中に戻る
        #expect(cursor.index == 0)
    }

    @Test func saveAndLoadRoundTrips() {
        let defaults = UserDefaults(suiteName: "widget-prefs-" + UUID().uuidString)!
        var p = WidgetPrefs()
        p.labelIds = ["l1", ""]
        p.showHours = false
        p.save(WidgetPrefsKey.medium, defaults: defaults)
        #expect(WidgetPrefs.load(WidgetPrefsKey.medium, defaults: defaults) == p)
        #expect(WidgetPrefs.load(WidgetPrefsKey.small, defaults: defaults) == WidgetPrefs())
    }
}
