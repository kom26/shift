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
                                 kind: spec.kind, requireApproval: spec.requireApproval, status: .active)
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

    func updateMine(calendarId: String, uid: String, displayName: String, sharedKeys: [String]) async throws {
        if let i = membersByCalendar[calendarId]?.firstIndex(where: { $0.id == uid }) {
            membersByCalendar[calendarId]?[i].displayName = displayName
            membersByCalendar[calendarId]?[i].sharedKeys = sharedKeys
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
