import Foundation
import Observation

/// 参加している共有カレンダー
struct SharedCalendar: Equatable, Identifiable {
    let id: String
    var name: String
    let ownerUid: String
}

/// 招待コード。共有カレンダーの ID と招待の合言葉をつなげたもの(英数字とハイフンだけ)
struct InviteCode: Equatable {
    let calendarId: String
    let token: String

    var text: String { "\(calendarId)-\(token)" }

    /// 貼り付けた文字から取り出す。前後の空白や、リンクの途中にあっても最後の 1 区切りを見る
    static func parse(_ raw: String) -> InviteCode? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = trimmed.split(whereSeparator: { $0 == "/" || $0 == " " }).last.map(String.init) ?? ""
        let parts = last.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(isAllowed) }) else { return nil }
        return InviteCode(calendarId: parts[0], token: parts[1])
    }

    private static func isAllowed(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber) }

    static func random(length: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<length).map { _ in alphabet.randomElement()! })
    }
}

/// 共有カレンダーのクラウド側(テストでは差し替える)
protocol CalendarBacking: AnyObject {
    /// カレンダーを作り、作った人を持ち主として参加させる。最初の招待コードを返す
    func create(uid: String, name: String) async throws -> (calendar: SharedCalendar, invite: InviteCode)
    func joined(uid: String) async throws -> [SharedCalendar]
    /// 招待コードで参加する。コードが無効なら CalendarError.invalidInvite
    func join(uid: String, code: InviteCode) async throws -> SharedCalendar
    /// 有効な招待コード。無ければ作る
    func currentInvite(uid: String, calendar: SharedCalendar) async throws -> InviteCode
    func leave(uid: String, calendarId: String) async throws
}

enum CalendarError: Error, Equatable {
    case invalidInvite
}

/// 共有カレンダーの一覧と、作成・参加・退出
@MainActor
@Observable
final class CalendarService {
    private(set) var calendars: [SharedCalendar] = []
    private(set) var busy = false
    var errorMessage: String?

    private let backing: CalendarBacking
    private var uid: String?

    init(backing: CalendarBacking) {
        self.backing = backing
    }

    func start(uid: String) async {
        self.uid = uid
        calendars = []
        do {
            let list = try await backing.joined(uid: uid)
            guard self.uid == uid else { return }
            calendars = list
        } catch {
            // 取れなかったときは一覧が空のまま。ドロワーを開き直したときに取り直す
        }
    }

    func stop() {
        uid = nil
        calendars = []
    }

    @discardableResult
    func create(name: String) async -> (calendar: SharedCalendar, invite: InviteCode)? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uid, !trimmed.isEmpty else { return nil }
        return await run("共有カレンダーを作れませんでした") {
            let made = try await self.backing.create(uid: uid, name: trimmed)
            self.calendars.append(made.calendar)
            return made
        }
    }

    @discardableResult
    func join(code raw: String) async -> SharedCalendar? {
        guard let uid else { return nil }
        guard let code = InviteCode.parse(raw) else {
            errorMessage = "招待コードの形が正しくありません"
            return nil
        }
        if let existing = calendars.first(where: { $0.id == code.calendarId }) { return existing }
        return await run("参加できませんでした", invalid: "招待コードが無効か、期限が切れています") {
            let joined = try await self.backing.join(uid: uid, code: code)
            self.calendars.append(joined)
            return joined
        }
    }

    func invite(for calendar: SharedCalendar) async -> InviteCode? {
        guard let uid else { return nil }
        return await run("招待コードを取得できませんでした") {
            try await self.backing.currentInvite(uid: uid, calendar: calendar)
        }
    }

    func leave(_ calendar: SharedCalendar) async {
        guard let uid, calendar.ownerUid != uid else { return }
        _ = await run("退出できませんでした") {
            try await self.backing.leave(uid: uid, calendarId: calendar.id)
            self.calendars.removeAll { $0.id == calendar.id }
        }
    }

    private func run<T>(_ failure: String, invalid: String? = nil, _ body: () async throws -> T) async -> T? {
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            return try await body()
        } catch CalendarError.invalidInvite {
            errorMessage = invalid ?? failure
        } catch {
            errorMessage = failure
        }
        return nil
    }
}
