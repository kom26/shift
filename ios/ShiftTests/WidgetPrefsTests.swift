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

    @Test func kindsStartAllShownAndCanBeTurnedOffOneByOne() {
        let w = ["w1", "w2"], l = ["l1", Store.noLabelKey]
        var p = WidgetPrefs()
        #expect(p.shows("w1", workplace: true) && p.shows(Store.noLabelKey, workplace: false) && p.showTasks)

        // 1 つ外すと、残りを見せる
        p.toggleShown("w1", workplace: true, allWorkplaces: w, allLabels: l)
        #expect(!p.shows("w1", workplace: true) && p.shows("w2", workplace: true) && p.shows("l1", workplace: false))

        // 戻すと、絞らない(空)に戻る
        p.toggleShown("w1", workplace: true, allWorkplaces: w, allLabels: l)
        #expect(p.workplaceIds.isEmpty && p.labelIds.isEmpty)

        // 全部外すと、何も見せない(空=全部 にならない)
        for id in w { p.toggleShown(id, workplace: true, allWorkplaces: w, allLabels: l) }
        for id in l { p.toggleShown(id, workplace: false, allWorkplaces: w, allLabels: l) }
        #expect(p.labelIds == [WidgetPrefs.noneKey])
        #expect(!p.shows("w1", workplace: true) && !p.shows("l1", workplace: false))

        // そこから 1 つ入れると、それだけ見せる
        p.toggleShown("l1", workplace: false, allWorkplaces: w, allLabels: l)
        #expect(p.labelIds == ["l1"] && p.workplaceIds.isEmpty)
    }

    @Test func oldSavedPrefsShowTasks() throws {
        let old = #"{"calendarIds":[""],"workplaceIds":[],"labelIds":[],"showBirthdays":true}"#
        let p = try JSONDecoder().decode(WidgetPrefs.self, from: Data(old.utf8))
        #expect(p.showTasks)
    }
}
