import UIKit
import Foundation
import Testing
@testable import Shift

private final class FakeSharedEvents: SharedEventsBacking {
    var docs: [String: [String: SharedEvent]] = [:]
    var sets = 0
    var deletes = 0

    func fetch(calendarId: String) async throws -> [SharedEvent] { Array((docs[calendarId] ?? [:]).values) }
    func listen(calendarId: String, onChange: @escaping ([SharedEvent]) -> Void) -> () -> Void { {} }

    func set(calendarId: String, event: SharedEvent) async throws {
        sets += 1
        docs[calendarId, default: [:]][event.id] = event
    }

    func delete(calendarId: String, id: String) async throws {
        deletes += 1
        docs[calendarId]?[id] = nil
    }

    func mineIds(calendarId: String, uid: String) async throws -> Set<String> {
        Set((docs[calendarId] ?? [:]).values.filter { $0.ownerUid == uid }.map(\.id))
    }
}

@MainActor
struct SharedEventsTests {
    private func makeStore() -> Store {
        let name = UUID().uuidString
        return Store(fileURL: FileManager.default.temporaryDirectory.appending(path: "\(name).json"),
                     defaults: UserDefaults(suiteName: name)!)
    }

    private func calendar(keys: [String], kind: CalendarKind = .mutual, owner: String = "me",
                          status: MemberStatus = .active) -> SharedCalendar {
        SharedCalendar(id: "c1", name: "家族", ownerUid: owner, kind: kind, requireApproval: false,
                       status: status, mySharedKeys: keys)
    }

    private func event(_ id: String, title: String = "t", label: String? = nil, workplace: String? = nil) -> ShiftEvent {
        var e = ev(id, "2026-11-10")
        e.title = title
        e.memo = "秘密のメモ"
        e.labelId = label
        e.workplaceId = workplace
        e.adjustment = 5000
        return e
    }

    @Test func sharedCopyKeepsOnlyPublicFields() {
        let store = makeStore()
        store.addWorkplace(Workplace(id: "w1", name: "ドンキ", color: "#ef4444", hourlyWage: 1500))
        let shared = SharedEvent.make(from: event("e1", title: "早番", workplace: "w1"), uid: "me", store: store)
        #expect(shared?.id == "me_e1")
        #expect(shared?.sourceKey == "w:w1")
        #expect(shared?.name == "ドンキ")
        #expect(shared?.title == "早番")
        let dump = String(describing: shared)
        #expect(!dump.contains("秘密のメモ"))
        #expect(!dump.contains("5000"))
        #expect(!dump.contains("1500"))
    }

    @Test func labelAndUnspecifiedEventsAreKeyedByLabel() {
        let store = makeStore()
        let date = store.addLabel(name: "デート", color: "#111111")!
        #expect(SharedEvent.make(from: event("a", label: date.id), uid: "me", store: store)?.sourceKey == "l:\(date.id)")
        #expect(SharedEvent.make(from: event("b"), uid: "me", store: store)?.sourceKey == "l:")
        #expect(SharedEvent.make(from: event("b"), uid: "me", store: store)?.name == "")
    }

    @Test func unplacedEventsAreNotShared() {
        let store = makeStore()
        #expect(SharedEvent.make(from: ev("u", nil, placed: false), uid: "me", store: store) == nil)
    }

    @Test func onlyEventsOfTheSharedItemsAreUploaded() async {
        let store = makeStore()
        let date = store.addLabel(name: "デート", color: "#111111")!
        store.save(event("a", label: date.id))
        store.save(event("b"))
        let backing = FakeSharedEvents()
        let cal = calendar(keys: ["l:\(date.id)"])
        let publisher = SharedPublisher(backing: backing, store: store, calendars: { [cal] in [cal] }, uid: { "me" })
        await publisher.syncNow()
        #expect(Set(backing.docs["c1"]?.keys.map { $0 } ?? []) == ["me_a"])
    }

    @Test func unchangedEventsAreNotSentAgainAndChangesAreDiffed() async {
        let store = makeStore()
        store.save(event("a", title: "一つ目"))
        let backing = FakeSharedEvents()
        let cal = calendar(keys: ["l:"])
        let publisher = SharedPublisher(backing: backing, store: store, calendars: { [cal] in [cal] }, uid: { "me" })
        await publisher.syncNow()
        await publisher.syncNow()
        #expect(backing.sets == 1)
        store.save(event("a", title: "直した"))
        store.save(event("b"))
        await publisher.syncNow()
        #expect(backing.sets == 3)
        #expect(backing.docs["c1"]?["me_a"]?.title == "直した")
    }

    @Test func deletedOrUnsharedEventsAreRemovedFromTheCalendar() async {
        let store = makeStore()
        store.save(event("a"))
        store.save(event("b"))
        let backing = FakeSharedEvents()
        let cal = calendar(keys: ["l:"])
        let publisher = SharedPublisher(backing: backing, store: store, calendars: { [cal] in [cal] }, uid: { "me" })
        await publisher.syncNow()
        store.delete(id: "a")
        await publisher.syncNow()
        #expect(Set(backing.docs["c1"]?.keys.map { $0 } ?? []) == ["me_b"])

        let off = calendar(keys: [])
        let stopped = SharedPublisher(backing: backing, store: store, calendars: { [off] in [off] }, uid: { "me" })
        await stopped.syncNow()
        #expect(backing.docs["c1"]?.isEmpty == true)
    }

    @Test func leftoverDocsFromAnEarlierSessionAreCleanedOnTheFirstSync() async {
        let store = makeStore()
        store.save(event("keep"))
        let backing = FakeSharedEvents()
        backing.docs["c1"] = [
            "me_old": SharedEvent(id: "me_old", ownerUid: "me", sourceKey: "l:", title: "古い", startDate: "2026-11-01",
                                  endDate: "2026-11-01", startTime: nil, endTime: nil, allDay: true, name: "", color: "#bec1cc"),
            "you_x": SharedEvent(id: "you_x", ownerUid: "you", sourceKey: "l:", title: "他人", startDate: "2026-11-01",
                                 endDate: "2026-11-01", startTime: nil, endTime: nil, allDay: true, name: "", color: "#bec1cc"),
        ]
        let cal = calendar(keys: ["l:"])
        let publisher = SharedPublisher(backing: backing, store: store, calendars: { [cal] in [cal] }, uid: { "me" })
        await publisher.syncNow()
        #expect(Set(backing.docs["c1"]?.keys.map { $0 } ?? []) == ["me_keep", "you_x"])
    }

    @Test func guestsOfAOnewayCalendarAndPendingMembersPublishNothing() async {
        let store = makeStore()
        store.save(event("a"))
        let backing = FakeSharedEvents()
        let guest = calendar(keys: ["l:"], kind: .oneway, owner: "owner")
        let pending = calendar(keys: ["l:"], status: .pending)
        let publisher = SharedPublisher(backing: backing, store: store, calendars: { [guest, pending] in [guest, pending] },
                                        uid: { "me" })
        await publisher.syncNow()
        #expect(backing.sets == 0)
        #expect(!guest.canPublish(uid: "me"))
        #expect(!pending.canPublish(uid: "me"))
        #expect(calendar(keys: [], kind: .oneway, owner: "me").canPublish(uid: "me"))
    }

    private func shared(_ id: String, owner: String, key: String, title: String, name: String = "", color: String = "#bec1cc") -> SharedEvent {
        SharedEvent(id: id, ownerUid: owner, sourceKey: key, title: title, startDate: "2026-11-10", endDate: "2026-11-10",
                    startTime: nil, endTime: nil, allDay: true, name: name, color: color)
    }

    @Test func sharedViewStoreShowsEveryMembersEventsWithPlainTitles() {
        let events = [
            shared("me_a", owner: "me", key: "l:", title: "ランチ"),
            shared("you_b", owner: "you", key: "w:w1", title: "早番", name: "ドンキ", color: "#ef4444"),
        ]
        let store = SharedViewState.makeStore(events: events, overrides: [:])
        #expect(Set(store.events.map(\.title)) == ["ランチ", "早番"])
        #expect(store.events.allSatisfy { $0.placed && $0.barShowsTitle == true })
    }

    @Test func colorOverridesApplyPerOwnerAndSourceNotToOthers() {
        let mine = shared("me_a", owner: "me", key: "w:w1", title: "早番", color: "#ef4444")
        let yours = shared("you_a", owner: "you", key: "w:w1", title: "早番", color: "#ef4444")
        let calendarOwned = SharedEvent.newInCalendar(uid: "me", date: "2026-11-10")
        let overrides = [SharedViewState.colorKey(for: mine): "#111111", SharedViewState.colorKey(for: calendarOwned): "#222222"]
        #expect(SharedViewState.colorKey(for: mine) != SharedViewState.colorKey(for: yours))
        let store = SharedViewState.makeStore(events: [mine, yours, calendarOwned], overrides: overrides)
        func color(_ id: String) -> String? { store.events.first { $0.id == id }?.color }
        #expect(color("me_a") == "#111111")
        #expect(color("you_a") == "#ef4444")
        #expect(color(calendarOwned.id) == "#222222")
    }

    @Test func barFollowsTheSharersDisplayUnlessPickedHere() {
        func timed(_ id: String, owner: String, key: String) -> SharedEvent {
            SharedEvent(id: id, ownerUid: owner, sourceKey: key, title: "早番", startDate: "2026-11-10", endDate: "2026-11-10",
                        startTime: "09:00", endTime: "17:00", allDay: false, name: "", color: "#ef4444")
        }
        var mine = timed("me_a", owner: "me", key: "w:w1")
        var yours = timed("you_a", owner: "you", key: "w:w1")
        var other = timed("you_c", owner: "you", key: "w:w2")
        mine.barTime = false      // 共有した人が予定名を出している
        yours.barTime = true      // 共有した人が時間を出している
        other.barTime = true
        let allDay = shared("me_b", owner: "me", key: "w:w1", title: "休み")
        // この端末で、自分の w:w1 だけ「時間」、相手の w:w2 だけ「予定名」を選ぶ
        let modes = [SharedViewState.colorKey(for: mine): true, SharedViewState.colorKey(for: other): false]
        let store = SharedViewState.makeStore(events: [mine, yours, other, allDay], overrides: [:], timeModes: modes)
        func shows(_ id: String) -> Bool? { store.events.first { $0.id == id }?.barShowsTime }
        #expect(shows("me_a") == true)      // 選んだ表示が優先
        #expect(shows("you_a") == true)     // 選んでいないので、共有した人の表示(時間)
        #expect(shows("you_c") == false)    // 予定名を選んだ
        // 時間のない予定は、時間を選んでいても予定名のまま
        #expect(shows("me_b") == false)
    }

    @Test func avatarBackgroundCanBeChosenForTheInitial() {
        #expect(UserAvatar.customBackground("") == nil)
        #expect(UserAvatar.customBackground("img:AAAA") == nil)
        #expect(UserAvatar.customBackground("bg:#e0707a") == "#e0707a")
        #expect(UserAvatar.backgroundChoices.contains("#6a8cf0"))
    }

    @Test func avatarColorIsStableAndInitialIsTheFirstCharacter() {
        #expect(UserAvatar.color(for: "abc123") == UserAvatar.color(for: "abc123"))
        #expect(UserAvatar.initial(of: " ゆう ") == "ゆ")
        #expect(UserAvatar.initial(of: "") == "?")
    }

    @Test func photoAvatarIsCroppedToASquareAndRoundTrips() throws {
        // 横長(400x200)の写真でも、正方形に切り取って取り込む
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let wide = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 200), format: format).image { c in
            UIColor.red.setFill()
            c.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        }
        let png = try #require(wide.pngData())
        let encoded = try #require(AvatarPhoto.encode(png))
        #expect(AvatarPhoto.isPhoto(encoded))
        let decoded = try #require(AvatarPhoto.image(from: encoded))
        #expect(decoded.size.width == decoded.size.height)
        #expect(!AvatarPhoto.isPhoto("🐶"))
        #expect(AvatarPhoto.image(from: "🐶") == nil)
        #expect(AvatarPhoto.encode(Data([1, 2, 3])) == nil)
    }
}

@MainActor
struct SharedCalendarEventTests {
    @Test func newEventInACalendarIsCalendarOwnedAndHasNoPayFields() {
        let e = SharedEvent.newInCalendar(uid: "me", date: "2026-11-10")
        #expect(e.isCalendarOwned)
        #expect(e.id.hasPrefix("cal_"))
        #expect(e.allDay)
        #expect(e.startDate == "2026-11-10" && e.endDate == "2026-11-10")
        #expect(e.name == "")
    }

    @Test func editorCombinesDateAndTime() {
        let d = SharedEventEditor.combine("2026-11-10", "09:30", fallbackHour: 18)
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        #expect(c.hour == 9 && c.minute == 30)
        let f = SharedEventEditor.combine("2026-11-10", nil, fallbackHour: 18)
        #expect(Calendar.current.component(.hour, from: f) == 18)
    }

    @Test func myPublishedCopiesAreCleanedButCalendarEventsAreKept() async {
        let backing = FakeSharedEventsForCalendar()
        backing.docs["c1"] = [
            "cal_x": SharedEvent.newInCalendar(uid: "me", date: "2026-11-10"),
            "me_old": SharedEvent(id: "me_old", ownerUid: "me", sourceKey: "l:", title: "古い", startDate: "2026-11-01",
                                  endDate: "2026-11-01", startTime: nil, endTime: nil, allDay: true, name: "", color: "#bec1cc"),
        ]
        let store = Store(fileURL: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json"),
                          defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let cal = SharedCalendar(id: "c1", name: "家族", ownerUid: "me", kind: .mutual, requireApproval: false,
                                 status: .active, mySharedKeys: ["l:"])
        let publisher = SharedPublisher(backing: backing, store: store, calendars: { [cal] in [cal] }, uid: { "me" })
        await publisher.syncNow()
        #expect(Set(backing.docs["c1"]?.keys.map { $0 } ?? []) == ["cal_x"])
    }
}

private final class FakeSharedEventsForCalendar: SharedEventsBacking {
    var docs: [String: [String: SharedEvent]] = [:]
    func fetch(calendarId: String) async throws -> [SharedEvent] { Array((docs[calendarId] ?? [:]).values) }
    func listen(calendarId: String, onChange: @escaping ([SharedEvent]) -> Void) -> () -> Void { {} }
    func set(calendarId: String, event: SharedEvent) async throws { docs[calendarId, default: [:]][event.id] = event }
    func delete(calendarId: String, id: String) async throws { docs[calendarId]?[id] = nil }
    func mineIds(calendarId: String, uid: String) async throws -> Set<String> {
        Set((docs[calendarId] ?? [:]).values.filter { $0.ownerUid == uid }.map(\.id))
    }
}
