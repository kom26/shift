import Foundation
import Testing
@testable import Shift

private final class FakeCalendars: CalendarBacking {
    var calendars: [String: SharedCalendar] = [:]
    var membersByCalendar: [String: [CalendarMember]] = [:]
    var validTokens: [String: String] = [:]
    var fail = false

    func create(uid: String, spec: NewCalendar) async throws -> (calendar: SharedCalendar, invite: InviteCode) {
        if fail { throw URLError(.notConnectedToInternet) }
        let cal = SharedCalendar(id: "c\(calendars.count)", name: spec.name, ownerUid: uid,
                                 kind: spec.kind, requireApproval: spec.requireApproval, status: .active, icon: spec.icon)
        calendars[cal.id] = cal
        membersByCalendar[cal.id] = [CalendarMember(id: uid, displayName: spec.displayName, isOwner: true,
                                                    status: .active, sharedKeys: spec.sharedKeys)]
        validTokens[cal.id] = "tok\(calendars.count)"
        return (cal, InviteCode(calendarId: cal.id, token: validTokens[cal.id]!))
    }

    func joined(uid: String) async throws -> [SharedCalendar] {
        calendars.values.filter { c in membersByCalendar[c.id]?.contains { $0.id == uid } == true }.sorted { $0.id < $1.id }
    }

    func preview(code: InviteCode) async throws -> InvitePreview {
        guard validTokens[code.calendarId] == code.token, let c = calendars[code.calendarId] else {
            throw CalendarError.invalidInvite
        }
        return InvitePreview(calendarName: c.name, ownerName: "持ち主", kind: c.kind, requireApproval: c.requireApproval)
    }

    func join(uid: String, code: InviteCode, displayName: String, sharedKeys: [String]) async throws -> SharedCalendar {
        guard validTokens[code.calendarId] == code.token, var c = calendars[code.calendarId] else {
            throw CalendarError.invalidInvite
        }
        let status: MemberStatus = c.requireApproval ? .pending : .active
        membersByCalendar[c.id, default: []].append(
            CalendarMember(id: uid, displayName: displayName, isOwner: false, status: status,
                           sharedKeys: c.kind == .oneway ? [] : sharedKeys))
        c.status = status
        return c
    }

    func currentInvite(uid: String, calendar: SharedCalendar) async throws -> InviteCode {
        InviteCode(calendarId: calendar.id, token: validTokens[calendar.id] ?? "new")
    }

    func leave(uid: String, calendarId: String) async throws {
        membersByCalendar[calendarId]?.removeAll { $0.id == uid }
    }

    func deleteCalendar(calendarId: String, uid: String) async throws {
        calendars[calendarId] = nil
        membersByCalendar[calendarId] = nil
        validTokens[calendarId] = nil
    }

    func members(calendarId: String) async throws -> [CalendarMember] { membersByCalendar[calendarId] ?? [] }

    func setStatus(calendarId: String, uid: String, status: MemberStatus) async throws {
        if let i = membersByCalendar[calendarId]?.firstIndex(where: { $0.id == uid }) {
            membersByCalendar[calendarId]?[i].status = status
        }
    }

    func removeMember(calendarId: String, uid: String) async throws {
        membersByCalendar[calendarId]?.removeAll { $0.id == uid }
    }

    func updateCalendar(calendarId: String, uid: String, name: String, icon: String, requireApproval: Bool) async throws {
        calendars[calendarId]?.name = name
        calendars[calendarId]?.icon = icon
        calendars[calendarId]?.requireApproval = requireApproval
    }

    func updateMine(calendarId: String, uid: String, displayName: String, sharedKeys: [String], avatar: String,
                    shareManual: Bool) async throws {
        if let i = membersByCalendar[calendarId]?.firstIndex(where: { $0.id == uid }) {
            membersByCalendar[calendarId]?[i].displayName = displayName
            membersByCalendar[calendarId]?[i].sharedKeys = sharedKeys
            membersByCalendar[calendarId]?[i].avatar = avatar
            membersByCalendar[calendarId]?[i].shareManual = shareManual
        }
    }
}

@MainActor
struct CalendarServiceTests {
    private func spec(_ name: String = "家族", kind: CalendarKind = .mutual, approval: Bool = false,
                      keys: [String] = ["w:w1"]) -> NewCalendar {
        NewCalendar(name: name, displayName: "わたし", kind: kind, requireApproval: approval, sharedKeys: keys)
    }

    @Test func inviteCodeRoundTripsAndRejectsMalformedText() {
        let code = InviteCode(calendarId: "abc123", token: "xyz789")
        #expect(InviteCode.parse(code.text) == code)
        #expect(InviteCode.parse("  \(code.text)\n") == code)
        #expect(InviteCode.parse("https://shift-palette.web.app/join/\(code.text)") == code)
        #expect(InviteCode.parse("abc123") == nil)
        #expect(InviteCode.parse("a-b-c") == nil)
        #expect(InviteCode.parse("-xyz") == nil)
        #expect(InviteCode.parse("あ-い") == nil)
        #expect(InviteCode.parse("") == nil)
    }

    @Test func inviteLinkContainsTheCodeAndParsesBack() {
        let code = InviteCode(calendarId: "abc123", token: "xyz789")
        #expect(code.link?.absoluteString == "https://shift-palette.web.app/join/abc123-xyz789")
        #expect(InviteCode.parse(code.link?.absoluteString ?? "") == code)
    }

    @Test func randomIdsUseOnlySafeCharacters() {
        let id = InviteCode.random(length: 16)
        #expect(id.count == 16)
        #expect(InviteCode.parse("\(id)-\(id)") != nil)
    }

    @Test func shareKeysSeparateWorkplacesFromLabels() {
        #expect(ShareKey.workplace("w1") == "w:w1")
        #expect(ShareKey.label("x") == "l:x")
        #expect(ShareKey.label(nil) == "l:")
    }

    @Test func qrCodeIsDrawnForTheLinkAndPaddedForSaving() {
        let image = QRCode.image(for: "https://shift-palette.web.app/join/abc-def")
        #expect(image != nil)
        if let image {
            #expect(QRCode.padded(image, margin: 20).size.width == image.size.width + 40)
        }
    }

    @Test func createdCalendarAppearsInTheListWithItsSettings() async {
        let service = CalendarService(backing: FakeCalendars())
        await service.start(uid: "me")
        let made = await service.create(spec("  家族 ", kind: .oneway, approval: true))
        #expect(made?.calendar.name == "家族")
        #expect(made?.calendar.ownerUid == "me")
        #expect(made?.calendar.kind == .oneway)
        #expect(made?.calendar.requireApproval == true)
        #expect(service.calendars.map(\.name) == ["家族"])
    }

    @Test func iconsFallBackToTheDefaultWhenUnknown() {
        #expect(CalendarIcon.choices.count == 12)
        #expect(CalendarIcon.resolved("heart.fill") == "heart.fill")
        #expect(CalendarIcon.resolved("") == CalendarIcon.defaultName)
        #expect(CalendarIcon.resolved("no.such.symbol") == CalendarIcon.defaultName)
    }

    @Test func ownerCanChangeNameIconAndApprovalAndOpeningApprovalAdmitsEveryoneWaiting() async {
        let backing = FakeCalendars()
        let owner = CalendarService(backing: backing)
        await owner.start(uid: "me")
        var request = spec("家族", approval: true)
        request.icon = "heart.fill"
        let made = await owner.create(request)
        let calendar = made!.calendar
        #expect(calendar.icon == "heart.fill")

        // 許可制のまま、申請者が 2 人入った
        let a = CalendarService(backing: backing)
        await a.start(uid: "a")
        let b = CalendarService(backing: backing)
        await b.start(uid: "b")
        _ = await a.join(code: made!.invite, displayName: "A", sharedKeys: [])
        _ = await b.join(code: made!.invite, displayName: "B", sharedKeys: [])
        #expect(backing.membersByCalendar[calendar.id]?.filter { $0.status == .pending }.count == 2)

        // 許可制をやめると、申請中の人は全員承認される
        let ok = await owner.updateCalendar(calendar, name: "  カップル  ", icon: "house.fill", requireApproval: false)
        #expect(ok)
        #expect(backing.membersByCalendar[calendar.id]?.allSatisfy { $0.status == .active } == true)
        #expect(owner.calendars.first?.name == "カップル")
        #expect(owner.calendars.first?.icon == "house.fill")
        #expect(owner.calendars.first?.requireApproval == false)
        #expect(backing.calendars[calendar.id]?.name == "カップル")
    }

    @Test func onlyTheOwnerCanChangeTheCalendar() async {
        let backing = FakeCalendars()
        let owner = CalendarService(backing: backing)
        await owner.start(uid: "me")
        let made = await owner.create(spec())
        let member = CalendarService(backing: backing)
        await member.start(uid: "you")
        let joined = await member.join(code: made!.invite, displayName: "あなた", sharedKeys: [])
        #expect(await member.updateCalendar(joined!, name: "のっとり", icon: "star.fill", requireApproval: true) == false)
        #expect(backing.calendars[made!.calendar.id]?.name == "家族")
        #expect(await owner.updateCalendar(made!.calendar, name: "   ", icon: "star.fill", requireApproval: false) == false)
    }

    @Test func blankNamesOrSignedOutCreateNothing() async {
        let service = CalendarService(backing: FakeCalendars())
        #expect(await service.create(spec()) == nil)
        await service.start(uid: "me")
        #expect(await service.create(spec("   ")) == nil)
        var noName = spec()
        noName.displayName = "  "
        #expect(await service.create(noName) == nil)
        #expect(service.calendars.isEmpty)
    }

    @Test func previewShowsTheInviteBeforeJoining() async {
        let backing = FakeCalendars()
        let owner = CalendarService(backing: backing)
        await owner.start(uid: "owner")
        let made = await owner.create(spec(kind: .oneway, approval: true))!
        let guest = CalendarService(backing: backing)
        await guest.start(uid: "guest")
        let result = await guest.preview(code: made.invite.text)
        #expect(result?.preview.kind == .oneway)
        #expect(result?.preview.requireApproval == true)
        #expect(result?.code == made.invite)
    }

    @Test func joiningAMutualCalendarKeepsWhatIShare() async {
        let backing = FakeCalendars()
        let owner = CalendarService(backing: backing)
        await owner.start(uid: "owner")
        let made = await owner.create(spec())!
        let guest = CalendarService(backing: backing)
        await guest.start(uid: "guest")
        let joined = await guest.join(code: made.invite, displayName: "ゲスト", sharedKeys: ["l:"])
        #expect(joined?.status == .active)
        let members = await owner.members(of: made.calendar)
        #expect(members?.first { $0.id == "guest" }?.sharedKeys == ["l:"])
    }

    @Test func joiningAOnewayCalendarSharesNothing() async {
        let backing = FakeCalendars()
        let owner = CalendarService(backing: backing)
        await owner.start(uid: "owner")
        let made = await owner.create(spec(kind: .oneway))!
        let guest = CalendarService(backing: backing)
        await guest.start(uid: "guest")
        await guest.join(code: made.invite, displayName: "ゲスト", sharedKeys: ["w:w1"])
        let members = await owner.members(of: made.calendar)
        #expect(members?.first { $0.id == "guest" }?.sharedKeys == [])
    }

    @Test func approvalCalendarPutsGuestsOnHoldUntilTheOwnerApproves() async {
        let backing = FakeCalendars()
        let owner = CalendarService(backing: backing)
        await owner.start(uid: "owner")
        let made = await owner.create(spec(approval: true))!
        let guest = CalendarService(backing: backing)
        await guest.start(uid: "guest")
        let joined = await guest.join(code: made.invite, displayName: "ゲスト", sharedKeys: [])!
        #expect(joined.status == .pending)

        let pending = await owner.members(of: made.calendar)!.first { $0.id == "guest" }!
        #expect(pending.status == .pending)
        #expect(await guest.approve(pending, in: joined) == false)
        #expect(await owner.approve(pending, in: made.calendar))
        #expect(await owner.members(of: made.calendar)!.first { $0.id == "guest" }?.status == .active)
    }

    @Test func ownerCanRemoveAGuestButNotThemselves() async {
        let backing = FakeCalendars()
        let owner = CalendarService(backing: backing)
        await owner.start(uid: "owner")
        let made = await owner.create(spec())!
        let guest = CalendarService(backing: backing)
        await guest.start(uid: "guest")
        let joined = await guest.join(code: made.invite, displayName: "ゲスト", sharedKeys: [])!

        let all = await owner.members(of: made.calendar)!
        #expect(await owner.remove(all.first { $0.isOwner }!, from: made.calendar) == false)
        let g = all.first { $0.id == "guest" }!
        #expect(await guest.remove(g, from: joined) == false)
        #expect(await owner.remove(g, from: made.calendar))
        #expect(await owner.members(of: made.calendar)!.map(\.id) == ["owner"])
    }

    @Test func updatingMySettingsChangesNameAndSharedItems() async {
        let service = CalendarService(backing: FakeCalendars())
        await service.start(uid: "me")
        let made = await service.create(spec())!
        #expect(await service.updateMine(in: made.calendar, displayName: " ゆう ", sharedKeys: ["l:", "w:w2"]))
        let me = await service.members(of: made.calendar)!.first { $0.id == "me" }
        #expect(me?.displayName == "ゆう")
        #expect(me?.sharedKeys == ["l:", "w:w2"])
        #expect(await service.updateMine(in: made.calendar, displayName: "  ", sharedKeys: []) == false)
    }

    @Test func invalidOrMalformedCodeShowsAMessage() async {
        let service = CalendarService(backing: FakeCalendars())
        await service.start(uid: "me")
        #expect(await service.preview(code: "c9-wrong") == nil)
        #expect(service.errorMessage == "招待コードが無効か、期限が切れています")
        #expect(await service.preview(code: "なにか") == nil)
        #expect(service.errorMessage == "招待コードの形が正しくありません")
    }

    @Test func backingFailureSurfacesAsMessageNotCrash() async {
        let backing = FakeCalendars()
        backing.fail = true
        let service = CalendarService(backing: backing)
        await service.start(uid: "me")
        #expect(await service.create(spec()) == nil)
        #expect(service.errorMessage == "共有カレンダーを作れませんでした")
        #expect(!service.busy)
    }

    @Test func memberCanLeaveButOwnerCannot() async {
        let backing = FakeCalendars()
        let owner = CalendarService(backing: backing)
        await owner.start(uid: "owner")
        let made = await owner.create(spec())!
        let guest = CalendarService(backing: backing)
        await guest.start(uid: "guest")
        let joined = await guest.join(code: made.invite, displayName: "ゲスト", sharedKeys: [])!
        await guest.leave(joined)
        #expect(guest.calendars.isEmpty)
        await owner.leave(made.calendar)
        #expect(owner.calendars.map(\.id) == [made.calendar.id])
    }

    @Test func onlyTheOwnerCanDeleteACalendar() async {
        let backing = FakeCalendars()
        let owner = CalendarService(backing: backing)
        await owner.start(uid: "owner")
        let made = await owner.create(spec())!
        let guest = CalendarService(backing: backing)
        await guest.start(uid: "guest")
        let joined = await guest.join(code: made.invite, displayName: "ゲスト", sharedKeys: [])!
        #expect(await guest.delete(joined) == false)
        #expect(backing.calendars[made.calendar.id] != nil)
        #expect(await owner.delete(made.calendar))
        #expect(owner.calendars.isEmpty)
        #expect(backing.calendars[made.calendar.id] == nil)
    }

    @Test func stopClearsTheList() async {
        let service = CalendarService(backing: FakeCalendars())
        await service.start(uid: "me")
        await service.create(spec())
        service.stop()
        #expect(service.calendars.isEmpty)
        #expect(await service.create(spec("また")) == nil)
    }
}

private final class ListeningEvents: SharedEventsBacking {
    var docs: [String: [SharedEvent]] = [:]
    func fetch(calendarId: String) async throws -> [SharedEvent] { docs[calendarId] ?? [] }
    func listen(calendarId: String, onChange: @escaping ([SharedEvent]) -> Void) -> () -> Void {
        onChange(docs[calendarId] ?? [])
        return {}
    }
    func set(calendarId: String, event: SharedEvent) async throws {}
    func delete(calendarId: String, id: String) async throws {}
    func mineIds(calendarId: String, uid: String) async throws -> Set<String> { [] }
}

@MainActor
struct OverlayTests {
    private func plain(_ id: String, owner: String, key: String = "l:") -> SharedEvent {
        SharedEvent(id: id, ownerUid: owner, sourceKey: key, title: id, startDate: "2026-11-10", endDate: "2026-11-10",
                    startTime: nil, endTime: nil, allDay: true, name: "", color: "#bec1cc")
    }

    private func makeStore() -> Store {
        let name = UUID().uuidString
        return Store(fileURL: FileManager.default.temporaryDirectory.appending(path: "\(name).json"),
                     defaults: UserDefaults(suiteName: name)!)
    }

    @Test func storeShowsOverlayEventsButNeverSavesOrFiltersThem() {
        let store = makeStore()
        store.setOverlay([ev("x", "2026-11-10")])
        #expect(store.events.isEmpty)
        #expect(store.visibleEvents.map(\.id) == ["x"])
        #expect(store.daySummary(date: "2026-11-10").events.map(\.event.id) == ["x"])
        #expect(store.isOverlay("x"))
        store.toggleLabelFilter("none-such")
        #expect(store.visibleEvents.map(\.id) == ["x"])
    }

    @Test func overlayShowsOthersAndCalendarEventsButNotMyOwnCopies() async throws {
        let service = CalendarService(backing: FakeCalendars())
        await service.start(uid: "me")
        let made = try #require(await service.create(NewCalendar(name: "家族", displayName: "わたし", kind: .mutual,
                                                                  requireApproval: false, sharedKeys: [])))
        let backing = ListeningEvents()
        let calendarOwned = SharedEvent.newInCalendar(uid: "you", date: "2026-11-10")
        backing.docs[made.calendar.id] = [plain("me_a", owner: "me"), plain("you_b", owner: "you"), calendarOwned]
        let name = UUID().uuidString
        let view = SharedViewState(events: backing, calendars: service, defaults: UserDefaults(suiteName: name)!)
        let store = makeStore()
        view.attach(store: store)
        view.setOverlay([made.calendar.id], on: true)
        try await Task.sleep(for: .milliseconds(200))
        #expect(Set(store.overlayEvents.map(\.id)) == ["you_b", calendarOwned.id])
        #expect(view.event("you_b") != nil)
        #expect(view.event("me_a") == nil)
        // 外すと消える
        view.setOverlay([made.calendar.id], on: false)
        #expect(store.overlayEvents.isEmpty)
    }
}
