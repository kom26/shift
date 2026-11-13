import Foundation
import Testing
@testable import Shift

@MainActor
struct PhotoAlbumTests {
    private func makeStore() -> Store {
        let name = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).json")
        return Store(fileURL: url, defaults: UserDefaults(suiteName: name)!)
    }

    private func event(_ id: String, _ date: String?, title: String, image: String?) -> ShiftEvent {
        var e = date.map { ShiftEvent.new(on: $0) } ?? ShiftEvent.newUnplaced()
        e.id = id
        e.title = title
        e.imageId = image
        return e
    }

    @Test func ownPhotosIncludeEventsAndTasksNewestFirstWithUndatedLast() {
        let store = makeStore()
        store.save(event("a", "2026-11-03", title: "キャンプ", image: "img-a"))
        store.save(event("b", "2026-11-22", title: "紅葉", image: "img-b"))
        store.save(event("c", "2026-11-10", title: "写真なし", image: nil))
        store.save(event("d", nil, title: "いつか", image: "img-d"))
        var task = TaskItem.new(dueDate: "2026-10-31")
        task.title = "レポート"
        task.imageId = "img-t"
        store.tasks = [task]

        let photos = PhotoAlbum.own(store: store)
        #expect(photos.map(\.imageId) == ["img-b", "img-a", "img-t", "img-d"])
        #expect(photos.first { $0.imageId == "img-t" }?.source == .task)

        let sections = PhotoAlbum.sections(photos)
        #expect(sections.map(\.title) == ["2026年11月", "2026年10月", "日付未定"])
        #expect(sections[0].photos.count == 2)
    }

    @Test func ownPhotosCanBeFilteredByWorkplaceLabelAndTasks() {
        let store = makeStore()
        store.addWorkplace(name: "カフェ", color: "#cccccc")
        let work = store.workplaces.first { $0.name == "カフェ" }!
        let label = store.addLabel(name: "旅行", color: "#aaaaaa")!
        var shift = event("w", "2026-11-01", title: "カフェ", image: "img-w")
        shift.workplaceId = work.id
        var trip = event("l", "2026-11-02", title: "温泉", image: "img-l")
        trip.labelId = label.id
        let plain = event("n", "2026-11-03", title: "散歩", image: "img-n")
        for e in [shift, trip, plain] { store.save(e) }
        var task = TaskItem.new(startDate: "2026-11-04")
        task.imageId = "img-t"
        store.tasks = [task]

        let photos = PhotoAlbum.own(store: store)
        #expect(PhotoAlbum.filtered(photos, by: .workplace(work.id)).map(\.imageId) == ["img-w"])
        #expect(PhotoAlbum.filtered(photos, by: .label(label.id)).map(\.imageId) == ["img-l"])
        #expect(PhotoAlbum.filtered(photos, by: .label(Store.noLabelKey)).map(\.imageId) == ["img-n"])
        #expect(PhotoAlbum.filtered(photos, by: .tasks).map(\.imageId) == ["img-t"])
        #expect(PhotoAlbum.filtered(photos, by: .all).count == 4)
    }

    @Test func sharedPhotosOnlyComeFromEventsMadeInTheCalendar() {
        var made = SharedEvent.newInCalendar(uid: "me", date: "2026-11-15")
        made.title = "水族館"
        made.imageId = "cal~c~1"
        // 自分の予定を共有に出したもの(画像は共有しない形だが、もし付いていても出さない)
        var published = SharedEvent.newInCalendar(uid: "me", date: "2026-11-16")
        published = SharedEvent(id: "me_x", ownerUid: "me", sourceKey: "w:abc", title: "バイト",
                                startDate: "2026-11-16", endDate: "2026-11-16", startTime: nil, endTime: nil,
                                allDay: true, name: "", color: published.color)
        published.imageId = "img-mine"
        let photos = PhotoAlbum.shared([made, published])
        #expect(photos.map(\.imageId) == ["cal~c~1"])
    }

    @Test func datesAreShownWithTheWeekday() {
        #expect(PhotoAlbum.shortDate("2026-11-22") == "11/22(日)")
        #expect(PhotoAlbum.longDate("2026-11-08") == "2026年11月8日(日)")
    }
}
