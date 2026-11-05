import Foundation
import Testing
@testable import Shift

private final class FakeSharedEvents: SharedEventsBacking {
    var docs: [String: [String: SharedEvent]] = [:]
    var sets = 0
    var deletes = 0

    func fetch(calendarId: String) async throws -> [SharedEvent] { Array((docs[calendarId] ?? [:]).values) }

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

    @Test func sharedViewStoreShowsEveryMembersEventsWithNames() {
        let events = [
            SharedEvent(id: "me_a", ownerUid: "me", sourceKey: "l:", title: "ランチ", startDate: "2026-11-10",
                        endDate: "2026-11-10", startTime: "12:00", endTime: "13:00", allDay: false, name: "", color: "#bec1cc"),
            SharedEvent(id: "you_b", ownerUid: "you", sourceKey: "w:w1", title: "早番", startDate: "2026-11-10",
                        endDate: "2026-11-10", startTime: nil, endTime: nil, allDay: true, name: "ドンキ", color: "#ef4444"),
        ]
        let store = SharedViewState.makeStore(events: events, names: ["me": "ゆう", "you": "あい"], showNames: true)
        #expect(Set(store.events.map(\.title)) == ["ゆう｜ランチ", "あい｜早番"])
        #expect(store.events.allSatisfy { $0.placed && $0.barShowsTitle == true })
        let plain = SharedViewState.makeStore(events: events, names: ["me": "ゆう"], showNames: false)
        #expect(Set(plain.events.map(\.title)) == ["ランチ", "早番"])
    }
}
