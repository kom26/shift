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
