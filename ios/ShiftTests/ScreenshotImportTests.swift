import Foundation
import Testing
import UIKit
@testable import Shift

@MainActor
struct ScreenshotImportTests {
    private func makeStore() -> Store {
        let name = UUID().uuidString
        return Store(fileURL: FileManager.default.temporaryDirectory.appending(path: "\(name).json"),
                     defaults: UserDefaults(suiteName: name)!)
    }

    private func line(_ date: String, _ start: String?, _ end: String?, off: Bool = false) -> ShiftLine {
        ShiftLine(date: date, start: start, end: end, off: off)
    }

    // MARK: サーバーの返事

    @Test func parsingKeepsGoodLinesSortedOneADayAndDropsBrokenOnes() {
        let raw: [[String: Any]] = [
            ["date": "2026-11-11", "start": "16:00", "end": "24:00", "off": false],
            ["date": "2026-11-08", "start": "17:00", "end": "21:00", "off": false],
            ["date": "2026-11-08", "start": "18:00", "end": "22:00", "off": false],
            ["date": "2026-11-10", "start": "09:00", "end": "10:00", "off": true],
            ["date": "2026-11-12", "start": "9:00", "end": NSNull(), "off": false],
            ["date": "いつか", "start": "09:00", "end": "10:00", "off": false],
        ]
        let lines = ShiftLine.parse(raw)
        #expect(lines.map(\.date) == ["2026-11-08", "2026-11-10", "2026-11-11"])
        #expect(lines[0].start == "18:00")
        #expect(lines[1].off && lines[1].start == nil && lines[1].end == nil)
        #expect(lines[2].end == "24:00")
        #expect(ShiftLine.parse(nil).isEmpty)
        #expect(ShiftLine.parse("x").isEmpty)
    }

    // MARK: 予定にする

    @Test func offDaysAreSkippedAndWorkplaceEventsGetHoursAndTheWorkplaceColor() {
        let store = makeStore()
        store.addWorkplace(Workplace(id: "w1", name: "ドンキ", color: "#ef4444", hourlyWage: 1500))
        let wp = store.workplaces[0]
        let events = ShiftLineImport.events(
            from: [line("2026-11-08", "17:00", "21:00"), line("2026-11-10", nil, nil, off: true), line("2026-11-11", "16:00", "24:00")],
            title: "バイト", workplace: wp, label: nil, store: store)
        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.title == "バイト" && $0.placed && $0.workplaceId == "w1" && $0.labelId == nil })
        #expect(events.allSatisfy { $0.color == "#ef4444" && $0.barShowsTitle == nil })
        #expect(events[0].startTime == "17:00" && events[0].endTime == "21:00" && events[0].endDate == "2026-11-08")
        #expect(events[0].workHours == 4)
        // 24:00 は、同じ日のまま
        #expect(events[1].endTime == "24:00" && events[1].endDate == "2026-11-11")
    }

    @Test func overnightShiftsEndTheNextDayAndLabelEventsShowTheirTitle() {
        let store = makeStore()
        let date = store.addLabel(name: "デート", color: "#f28dae")!
        let events = ShiftLineImport.events(from: [line("2026-11-30", "22:00", "06:30")], title: "夜勤", workplace: nil,
                                            label: date, store: store)
        #expect(events.count == 1)
        #expect(events[0].endDate == "2026-12-01")
        #expect(events[0].labelId == date.id && events[0].workplaceId == nil)
        #expect(events[0].color == "#f28dae")
        #expect(events[0].barShowsTitle == true)
    }

    @Test func lineWithoutTimesBecomesAnAllDayEvent() {
        let store = makeStore()
        let events = ShiftLineImport.events(from: [line("2026-11-14", nil, nil)], title: "予定", workplace: nil, label: nil, store: store)
        #expect(events.count == 1)
        #expect(events[0].allDay && events[0].startTime == nil && events[0].workHours == nil)
        #expect(events[0].color == EventLabel.noneColor)
    }

    // MARK: 読み取りの入口

    private struct FakeReader: ScreenshotReading {
        var result: [ShiftLine]
        func read(images: [Data]) async throws -> [ShiftLine] { result }
    }

    @Test func fakeReaderReturnsWhatItWasGiven() async throws {
        let reader: ScreenshotReading = FakeReader(result: [line("2026-11-08", "17:00", "21:00")])
        let got = try await reader.read(images: [Data([1])])
        #expect(got.count == 1)
    }

    // MARK: 画像を小さくする

    @Test func shrinkingKeepsTheLongSideWithinTheLimitAndNeverEnlarges() throws {
        func image(_ w: CGFloat, _ h: CGFloat) -> UIImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { c in
                UIColor.white.setFill()
                c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
        let big = try #require(ImageShrinker.jpeg(from: image(1170, 3000), maxSide: 1500))
        let bigImage = try #require(UIImage(data: big))
        #expect(max(bigImage.size.width, bigImage.size.height) <= 1500)
        let small = try #require(ImageShrinker.jpeg(from: image(300, 600), maxSide: 1500))
        let smallImage = try #require(UIImage(data: small))
        #expect(smallImage.size.height == 600)
    }
}

@MainActor
struct LastModifiedTests {
    private func makeStore() -> Store {
        let name = UUID().uuidString
        return Store(fileURL: FileManager.default.temporaryDirectory.appending(path: "\(name).json"),
                     defaults: UserDefaults(suiteName: name)!)
    }

    @Test func savingRecordsWhoAndWhenAndImportedEventsAreMarked() throws {
        let store = makeStore()
        store.editorName = "ゆう"
        store.save(ev("a", "2026-11-10"))
        let e = try #require(store.events.first)
        #expect(e.updatedBy == "ゆう")
        #expect(e.updatedAt != nil)
        #expect(e.lastModifiedText()?.hasPrefix("最終変更: ゆう ・ ") == true)
        #expect(e.lastModifiedText()?.hasSuffix("(画像取り込み)") == false)
        var imported = e
        imported.source = ShiftEvent.screenshotSource
        #expect(imported.lastModifiedText()?.hasSuffix("(画像取り込み)") == true)
        // 名前がないときは「自分」。動かしたときも、最終変更が更新される
        store.editorName = ""
        store.place(id: "a", on: "2026-11-12")
        #expect(store.events[0].lastModifiedText()?.contains("自分") == true)
        // 記録のない古い予定は、何も出さない
        #expect(ev("old", "2026-11-10").lastModifiedText() == nil)
    }

    @Test func copyAndDropMoveRecordTheChangerToo() throws {
        let store = makeStore()
        store.editorName = "ゆう"
        store.save(ev("a", "2026-11-10"))
        store.copy(id: "a", to: ["2026-11-15"])
        #expect(store.events.count == 2)
        #expect(store.events.allSatisfy { $0.updatedBy == "ゆう" })
        #expect(Set(store.events.compactMap(\.startDate)) == ["2026-11-10", "2026-11-15"])
    }
}
