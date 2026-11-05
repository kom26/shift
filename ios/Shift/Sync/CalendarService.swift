import Foundation
import Observation

/// 共有カレンダーの種類
enum CalendarKind: String, CaseIterable {
    /// 持ち主の予定を、招待した相手が見るだけ
    case oneway
    /// 参加した全員が、自分の予定を見せ合う
    case mutual

    var title: String { self == .oneway ? "見せるだけ" : "相互に共有" }
    var detail: String {
        self == .oneway ? "あなたの予定を、招待した相手が見るだけです。" : "参加した全員が、自分の予定を見せ合います。"
    }
}

enum MemberStatus: String {
    case active, pending
}

/// 参加している共有カレンダー
struct SharedCalendar: Equatable, Identifiable {
    let id: String
    var name: String
    let ownerUid: String
    var kind: CalendarKind = .mutual
    var requireApproval = false
    /// 自分の参加の状態。許可制で持ち主が承認するまでは pending
    var status: MemberStatus = .active
    /// 自分が共有に出している職場・ラベル(ShareKey の文字列)
    var mySharedKeys: [String] = []

    /// 自分の予定を共有に出せるか。見せるだけのカレンダーでは、持ち主だけ
    func canPublish(uid: String) -> Bool { status == .active && (kind == .mutual || ownerUid == uid) }
}

/// 共有カレンダーの参加者
struct CalendarMember: Equatable, Identifiable {
    let id: String
    var displayName: String
    var isOwner: Bool
    var status: MemberStatus
    /// 共有に出している職場・ラベル(ShareKey の文字列)
    var sharedKeys: [String]
}

/// 共有に出す項目のキー。職場は "w:<id>"、ラベルは "l:<id>"(「指定なし」は "l:")
enum ShareKey {
    static func workplace(_ id: String) -> String { "w:" + id }
    static func label(_ id: String?) -> String { "l:" + (id ?? "") }

    /// 予定が属する項目のキー。職場があれば職場、なければラベル
    static func of(_ event: ShiftEvent, store: Store) -> String {
        if let w = store.workplace(for: event) { return workplace(w.id) }
        return label(event.labelId)
    }
}

/// 招待の内容(参加する前に見せる)
struct InvitePreview: Equatable {
    let calendarName: String
    let ownerName: String
    let kind: CalendarKind
    let requireApproval: Bool
}

/// 招待コード。共有カレンダーの ID と招待の合言葉をつなげたもの(英数字とハイフンだけ)
struct InviteCode: Equatable {
    let calendarId: String
    let token: String

    var text: String { "\(calendarId)-\(token)" }

    /// 招待リンクの置き場所(Firebase Hosting)。開くとアプリが開く。アプリが無ければ TestFlight へ移る
    static let linkBase = "https://shift-palette.web.app/join/"
    var link: URL? { URL(string: Self.linkBase + text) }

    /// 貼り付けた文字から取り出す。前後の空白や、リンクの途中にあっても最後の 1 区切りを見る
    static func parse(_ raw: String) -> InviteCode? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = trimmed.split(whereSeparator: { $0 == "/" || $0 == " " || $0 == "\n" }).last.map(String.init) ?? ""
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

/// 作成時に決めること
struct NewCalendar: Equatable {
    var name: String
    /// 相手に見える自分の名前
    var displayName: String
    var kind: CalendarKind
    var requireApproval: Bool
    var sharedKeys: [String]
}

/// 共有カレンダーのクラウド側(テストでは差し替える)
protocol CalendarBacking: AnyObject {
    func create(uid: String, spec: NewCalendar) async throws -> (calendar: SharedCalendar, invite: InviteCode)
    func joined(uid: String) async throws -> [SharedCalendar]
    /// 招待の内容を見る。無効なら CalendarError.invalidInvite
    func preview(code: InviteCode) async throws -> InvitePreview
    /// 招待コードで参加する。許可制なら pending で入る。コードが無効なら CalendarError.invalidInvite
    func join(uid: String, code: InviteCode, displayName: String, sharedKeys: [String]) async throws -> SharedCalendar
    /// 有効な招待コード。無ければ作る
    func currentInvite(uid: String, calendar: SharedCalendar) async throws -> InviteCode
    func leave(uid: String, calendarId: String) async throws
    /// 持ち主が、カレンダーを予定・招待・参加者ごと消す
    func deleteCalendar(calendarId: String, uid: String) async throws
    func members(calendarId: String) async throws -> [CalendarMember]
    func setStatus(calendarId: String, uid: String, status: MemberStatus) async throws
    func removeMember(calendarId: String, uid: String) async throws
    func updateMine(calendarId: String, uid: String, displayName: String, sharedKeys: [String]) async throws
}

enum CalendarError: Error, Equatable {
    case invalidInvite
}

/// 共有カレンダーの一覧と、作成・参加・退出・参加者の管理
@MainActor
@Observable
final class CalendarService {
    private(set) var calendars: [SharedCalendar] = []
    private(set) var busy = false
    /// 参加の一覧や、自分の共有する項目が変わったとき(予定を共有に載せ直す合図)
    @ObservationIgnored var onChange: (() -> Void)?
    /// ログイン中の自分
    var myUid: String? { uid }
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
            onChange?()
        } catch {
            // 取れなかったときは一覧が空のまま。ドロワーを開き直したときに取り直す
        }
    }

    func stop() {
        uid = nil
        calendars = []
        onChange?()
    }

    @discardableResult
    func create(_ spec: NewCalendar) async -> (calendar: SharedCalendar, invite: InviteCode)? {
        var spec = spec
        spec.name = spec.name.trimmingCharacters(in: .whitespacesAndNewlines)
        spec.displayName = spec.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uid, !spec.name.isEmpty, !spec.displayName.isEmpty else { return nil }
        return await run("共有カレンダーを作れませんでした") {
            var made = try await self.backing.create(uid: uid, spec: spec)
            made.calendar.mySharedKeys = spec.sharedKeys
            self.calendars.append(made.calendar)
            self.onChange?()
            return made
        }
    }

    func preview(code raw: String) async -> (code: InviteCode, preview: InvitePreview)? {
        guard uid != nil else { return nil }
        guard let code = InviteCode.parse(raw) else {
            errorMessage = "招待コードの形が正しくありません"
            return nil
        }
        return await run("招待を確認できませんでした", invalid: "招待コードが無効か、期限が切れています") {
            let p = try await self.backing.preview(code: code)
            return (code, p)
        }
    }

    @discardableResult
    func join(code: InviteCode, displayName: String, sharedKeys: [String]) async -> SharedCalendar? {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uid, !name.isEmpty else { return nil }
        if let existing = calendars.first(where: { $0.id == code.calendarId }) { return existing }
        return await run("参加できませんでした", invalid: "招待コードが無効か、期限が切れています") {
            var joined = try await self.backing.join(uid: uid, code: code, displayName: name, sharedKeys: sharedKeys)
            joined.mySharedKeys = joined.kind == .oneway ? [] : sharedKeys
            self.calendars.append(joined)
            self.onChange?()
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
            self.onChange?()
        }
    }

    /// 持ち主が、共有カレンダーを消す。参加者の画面からも消える(予定のコピーも消えるが、みんなの元の予定は消えない)
    func delete(_ calendar: SharedCalendar) async -> Bool {
        guard let uid, calendar.ownerUid == uid else { return false }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            try await backing.deleteCalendar(calendarId: calendar.id, uid: uid)
            calendars.removeAll { $0.id == calendar.id }
            onChange?()
            return true
        } catch {
            // 原因が分かるように、元のエラーも添える
            errorMessage = "削除できませんでした\n\(error.localizedDescription)"
            return false
        }
    }

    func members(of calendar: SharedCalendar) async -> [CalendarMember]? {
        await run("参加者を取得できませんでした") { try await self.backing.members(calendarId: calendar.id) }
    }

    /// 持ち主が、承認待ちの人を承認する
    func approve(_ member: CalendarMember, in calendar: SharedCalendar) async -> Bool {
        guard uid == calendar.ownerUid else { return false }
        return await run("承認できませんでした") {
            try await self.backing.setStatus(calendarId: calendar.id, uid: member.id, status: .active)
            return true
        } ?? false
    }

    /// 持ち主が、参加者を削除する(承認待ちの却下も同じ)
    func remove(_ member: CalendarMember, from calendar: SharedCalendar) async -> Bool {
        guard uid == calendar.ownerUid, member.id != uid else { return false }
        return await run("削除できませんでした") {
            try await self.backing.removeMember(calendarId: calendar.id, uid: member.id)
            return true
        } ?? false
    }

    /// 自分の共有者名と、共有に出す項目を変える
    func updateMine(in calendar: SharedCalendar, displayName: String, sharedKeys: [String]) async -> Bool {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uid, !name.isEmpty else { return false }
        return await run("保存できませんでした") {
            try await self.backing.updateMine(calendarId: calendar.id, uid: uid, displayName: name, sharedKeys: sharedKeys)
            if let i = self.calendars.firstIndex(where: { $0.id == calendar.id }) { self.calendars[i].mySharedKeys = sharedKeys }
            self.onChange?()
            return true
        } ?? false
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
