import Testing
@testable import Shift

struct AnniversaryTests {
    @Test func birthdayAge() {
        let a = Anniversary(name: "A", kind: .birthday, year: 2000, month: 5, day: 3)
        #expect(a.occurs(on: "2026-05-03"))
        #expect(!a.occurs(on: "2026-05-04"))
        #expect(a.elapsedText(asOf: "2026-05-02") == "25歳")
        #expect(a.elapsedText(asOf: "2026-05-03") == "26歳")
        #expect(a.dateText == "2000年5月3日")
    }

    @Test func unknownYearHasNoAge() {
        let a = Anniversary(name: "A", kind: .birthday, year: nil, month: 5, day: 3)
        #expect(a.occurs(on: "2030-05-03"))
        #expect(a.elapsedText(asOf: "2030-05-03") == nil)
        #expect(a.dateText == "5月3日")
    }

    @Test func monthlyAnniversary() {
        let a = Anniversary(name: "B", kind: .anniversary, year: 2024, month: 3, day: 31, monthly: true)
        #expect(a.occurs(on: "2026-04-30"))   // 31日が無い月は月末
        #expect(!a.occurs(on: "2024-02-29"))  // 開始前
        #expect(a.elapsedText(asOf: "2026-05-31") == "2年2ヶ月")
        #expect(a.elapsedText(asOf: "2026-03-31") == "2年")
        #expect(a.elapsedText(asOf: "2024-04-30") == "1ヶ月")
    }

    @Test func yearlyAnniversary() {
        let a = Anniversary(name: "C", kind: .anniversary, year: 2020, month: 2, day: 29)
        #expect(a.occurs(on: "2027-02-28"))
        #expect(a.elapsedText(asOf: "2027-02-28") == "7周年")
    }
}
