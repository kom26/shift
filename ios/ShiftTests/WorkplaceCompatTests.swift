import Foundation
import Testing
@testable import Shift

struct WorkplaceCompatTests {
    @Test func oldWorkplaceJSONGetsDefaults() throws {
        let json = ##"{"id":"w","name":"ドンキ","color":"#f59e0b"}"##
        let w = try JSONDecoder().decode(Workplace.self, from: Data(json.utf8))
        #expect(w.id == "w")
        #expect(w.name == "ドンキ")
        #expect(w.hourlyWage == 0)
        #expect(w.transport == 0)
        #expect(w.weekdayBonus == [0, 0, 0, 0, 0, 0, 0])
        #expect(w.holidayBonus == 0)
        #expect(w.breakRules.isEmpty)
        #expect(w.breakFromNight == true)
    }

    @Test func weekdayBonusIsPaddedAndTruncated() throws {
        let short = ##"{"id":"w","name":"A","color":"#111","weekdayBonus":[1,2]}"##
        let w1 = try JSONDecoder().decode(Workplace.self, from: Data(short.utf8))
        #expect(w1.weekdayBonus == [1, 2, 0, 0, 0, 0, 0])
        let long = ##"{"id":"w","name":"A","color":"#111","weekdayBonus":[1,2,3,4,5,6,7,8,9]}"##
        let w2 = try JSONDecoder().decode(Workplace.self, from: Data(long.utf8))
        #expect(w2.weekdayBonus == [1, 2, 3, 4, 5, 6, 7])
    }

    @Test func oldEventJSONHasNilNewFields() throws {
        let json = ##"{"id":"e","title":"A","memo":"","color":"#111","startDate":"2026-10-20","endDate":"2026-10-20","placed":true,"allDay":true}"##
        let e = try JSONDecoder().decode(ShiftEvent.self, from: Data(json.utf8))
        #expect(e.workplaceId == nil)
        #expect(e.breakInNight == nil)
    }

    @Test func eventNewFieldsRoundTrip() throws {
        var e = ev("a", "2026-10-20")
        e.workplaceId = "w1"
        e.breakInNight = false
        let back = try JSONDecoder().decode(ShiftEvent.self, from: JSONEncoder().encode(e))
        #expect(back == e)
        #expect(back.workplaceId == "w1")
        #expect(back.breakInNight == false)
    }

    @Test func fullWorkplaceRoundTrip() throws {
        let w = Workplace(id: "w", name: "A", color: "#111111", hourlyWage: 1200, transport: 400,
                          weekdayBonus: [50, 0, 0, 0, 0, 0, 100], holidayBonus: 150,
                          breakRules: [BreakRule(id: "r", hours: 6, comparison: .atLeast, minutes: 30),
                                       BreakRule(id: "s", hours: 8, comparison: .over, minutes: 60)],
                          breakFromNight: false)
        let back = try JSONDecoder().decode(Workplace.self, from: JSONEncoder().encode(w))
        #expect(back == w)
    }

    @Test func storePersistsDetails() {
        let name = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).json")
        let defaults = UserDefaults(suiteName: name)!
        let store = Store(fileURL: url, defaults: defaults)
        store.addWorkplace(name: "A", color: "#111111")
        var w = store.workplaces[0]
        w.hourlyWage = 1100
        w.breakFromNight = false
        store.updateWorkplaceDetails(w)
        let reloaded = Store(fileURL: url, defaults: defaults)
        #expect(reloaded.workplaces == [w])
    }
}
