import Foundation
import Testing
@testable import Shift

private final class FakeCalendars: CalendarBacking {
    var stored: [SharedCalendar] = []
    var validTokens: [String: String] = [:]
    var fail = false

    func create(uid: String, name: String) async throws -> (calendar: SharedCalendar, invite: InviteCode) {
        if fail { throw URLError(.notConnectedToInternet) }
        let cal = SharedCalendar(id: "c\(stored.count)", name: name, ownerUid: uid)
        stored.append(cal)
        validTokens[cal.id] = "tok\(stored.count)"
        return (cal, InviteCode(calendarId: cal.id, token: validTokens[cal.id]!))
    }

    func joined(uid: String) async throws -> [SharedCalendar] { stored }

    func join(uid: String, code: InviteCode) async throws -> SharedCalendar {
        guard validTokens[code.calendarId] == code.token else { throw CalendarError.invalidInvite }
        return SharedCalendar(id: code.calendarId, name: "旅行", ownerUid: "owner")
    }

    func currentInvite(uid: String, calendar: SharedCalendar) async throws -> InviteCode {
        InviteCode(calendarId: calendar.id, token: validTokens[calendar.id] ?? "new")
    }

    func leave(uid: String, calendarId: String) async throws {
        stored.removeAll { $0.id == calendarId }
    }
}

@MainActor
struct CalendarServiceTests {
    @Test func inviteCodeRoundTripsAndRejectsMalformedText() {
        let code = InviteCode(calendarId: "abc123", token: "xyz789")
        #expect(InviteCode.parse(code.text) == code)
        #expect(InviteCode.parse("  \(code.text)\n") == code)
        #expect(InviteCode.parse("https://example.com/join/\(code.text)") == code)
        #expect(InviteCode.parse("abc123") == nil)
        #expect(InviteCode.parse("a-b-c") == nil)
        #expect(InviteCode.parse("-xyz") == nil)
        #expect(InviteCode.parse("あ-い") == nil)
        #expect(InviteCode.parse("") == nil)
    }

    @Test func randomIdsUseOnlySafeCharacters() {
        let id = InviteCode.random(length: 16)
        #expect(id.count == 16)
        #expect(InviteCode.parse("\(id)-\(id)") != nil)
    }

    @Test func createdCalendarAppearsInTheList() async {
        let service = CalendarService(backing: FakeCalendars())
        await service.start(uid: "me")
        let made = await service.create(name: "  家族 ")
        #expect(made?.calendar.name == "家族")
        #expect(made?.calendar.ownerUid == "me")
        #expect(service.calendars.map(\.name) == ["家族"])
    }

    @Test func blankNameOrSignedOutCreatesNothing() async {
        let service = CalendarService(backing: FakeCalendars())
        #expect(await service.create(name: "家族") == nil)
        await service.start(uid: "me")
        #expect(await service.create(name: "   ") == nil)
        #expect(service.calendars.isEmpty)
    }

    @Test func joiningWithAValidCodeAddsTheCalendarOnce() async {
        let backing = FakeCalendars()
        backing.validTokens["c9"] = "t9"
        let service = CalendarService(backing: backing)
        await service.start(uid: "me")
        #expect(await service.join(code: "c9-t9")?.id == "c9")
        #expect(await service.join(code: "c9-t9")?.id == "c9")
        #expect(service.calendars.count == 1)
    }

    @Test func invalidOrMalformedCodeShowsAMessage() async {
        let service = CalendarService(backing: FakeCalendars())
        await service.start(uid: "me")
        #expect(await service.join(code: "c9-wrong") == nil)
        #expect(service.errorMessage == "招待コードが無効か、期限が切れています")
        #expect(await service.join(code: "なにか") == nil)
        #expect(service.errorMessage == "招待コードの形が正しくありません")
        #expect(service.calendars.isEmpty)
    }

    @Test func backingFailureSurfacesAsMessageNotCrash() async {
        let backing = FakeCalendars()
        backing.fail = true
        let service = CalendarService(backing: backing)
        await service.start(uid: "me")
        #expect(await service.create(name: "家族") == nil)
        #expect(service.errorMessage == "共有カレンダーを作れませんでした")
        #expect(!service.busy)
    }

    @Test func memberCanLeaveButOwnerCannot() async {
        let backing = FakeCalendars()
        backing.validTokens["c9"] = "t9"
        let service = CalendarService(backing: backing)
        await service.start(uid: "me")
        let own = await service.create(name: "家族")!.calendar
        let other = await service.join(code: "c9-t9")!
        await service.leave(other)
        #expect(service.calendars.map(\.id) == [own.id])
        await service.leave(own)
        #expect(service.calendars.map(\.id) == [own.id])
    }

    @Test func stopClearsTheList() async {
        let service = CalendarService(backing: FakeCalendars())
        await service.start(uid: "me")
        await service.create(name: "家族")
        service.stop()
        #expect(service.calendars.isEmpty)
        #expect(await service.create(name: "また") == nil)
    }
}
