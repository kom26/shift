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
    /// ドロワーなどに出すアイコン(SF Symbols の名前。CalendarIcon.choices から選ぶ。写真のときは "img:" + base64)
    var icon: String = CalendarIcon.defaultName
    /// 自分の予定を、確認してから共有する(手動)か。false は、予定を変えるとすぐ共有する(自動)
    var myShareManual = false
    /// 自分が参加した時刻(Unix ミリ秒)。一覧を、参加した順に並べるのに使う(古い記録には無いので 0)
    var joinedAt: Double = 0

    /// 一覧の並び: 参加した順(古い順)。同じ時刻や、時刻が無いものは、ID の順。取り直しても、並びが変わらない
    static func ordered(_ list: [SharedCalendar]) -> [SharedCalendar] {
        list.sorted { ($0.joinedAt, $0.id) < ($1.joinedAt, $1.id) }
    }

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
    /// アバター。空なら名前の頭文字、bg: は背景色を選んだ頭文字、img: は写真(以前の絵文字も表示はできる)
    var avatar: String = ""
    /// 共有のしかたが手動か
    var shareManual = false
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
    var icon: String = CalendarIcon.defaultName
    /// この共有カレンダーでの自分のアバター(空は、名前の頭文字)
    var avatar: String = ""
}

/// 共有カレンダーのアイコン。仕事・暮らし・カップルなど、使い方に合わせて選ぶ
enum CalendarIcon {
    static let defaultName = "person.2.fill"

    /// 選べるアイコン(6 つずつ 2 段)
    static let choices: [(name: String, label: String)] = [
        ("person.2.fill", "みんな"), ("briefcase.fill", "仕事"), ("building.2.fill", "職場"),
        ("cart.fill", "お店"), ("fork.knife", "食事"), ("cup.and.saucer.fill", "カフェ"),
        ("heart.fill", "カップル"), ("house.fill", "家族"), ("star.fill", "お気に入り"),
        ("graduationcap.fill", "学校"), ("music.note", "趣味"), ("gamecontroller.fill", "ゲーム"),
    ]

    /// 写真のアイコンか(プロフィールのアバターと同じ "img:" + base64)
    static func isPhoto(_ icon: String) -> Bool { icon.hasPrefix(AvatarStyle.photoPrefix) && icon.count > AvatarStyle.photoPrefix.count }

    /// 色は、アイコンの名前のあとに "|#rrggbb" を付けて持つ(例 "briefcase.fill|#3b82f6")。
    /// 参加者全員に同じ色で見える。古い版では、名前が合わず標準のアイコンに見えるだけで、壊れない
    static let colorSeparator = "|"

    /// 記号の名前と、色(なければ nil)に分ける。写真は、色なし
    static func split(_ icon: String) -> (name: String, color: String?) {
        if isPhoto(icon) { return (icon, nil) }
        let parts = icon.components(separatedBy: colorSeparator)
        let color = parts.count > 1 ? parts[1] : nil
        return (parts[0], color.flatMap { $0.hasPrefix("#") && $0.count == 7 ? $0 : nil })
    }

    static func join(name: String, color: String?) -> String {
        guard let color, !isPhoto(name) else { return name }
        return name + colorSeparator + color
    }

    /// 保存してある名前が選択肢にないとき(古い版や別の版で作ったもの)は、標準のアイコンにする。写真はそのまま使う。色は残す
    static func resolved(_ icon: String) -> String {
        if isPhoto(icon) { return icon }
        let (name, color) = split(icon)
        return join(name: choices.contains { $0.name == name } ? name : defaultName, color: color)
    }
}

/// 共有カレンダーのクラウド側(テストでは差し替える)
protocol CalendarBacking: AnyObject {
    func create(uid: String, spec: NewCalendar) async throws -> (calendar: SharedCalendar, invite: InviteCode)
    func joined(uid: String) async throws -> [SharedCalendar]
    /// 招待の内容を見る。無効なら CalendarError.invalidInvite
    func preview(code: InviteCode) async throws -> InvitePreview
    /// 招待コードで参加する。許可制なら pending で入る。コードが無効なら CalendarError.invalidInvite
    func join(uid: String, code: InviteCode, displayName: String, sharedKeys: [String], avatar: String) async throws -> SharedCalendar
    /// 有効な招待コード。無ければ作る
    func currentInvite(uid: String, calendar: SharedCalendar) async throws -> InviteCode
    func leave(uid: String, calendarId: String) async throws
    /// いまの招待を無効にして、新しい招待を作る(持ち主)
    func reissueInvite(uid: String, calendar: SharedCalendar) async throws -> InviteCode
    /// 持ち主が、カレンダーを予定・招待・参加者ごと消す
    func deleteCalendar(calendarId: String, uid: String) async throws
    func members(calendarId: String) async throws -> [CalendarMember]
    /// 参加していたのに、削除された・外された共有カレンダー(一覧の記録も片づける)
    func goneCalendars(uid: String) async -> [GoneCalendar]
    /// 退会・削除のお知らせを残す(残った人が、次に開いたときに見る)
    func addNotice(calendarId: String, kind: String, name: String, byUid: String) async throws
    func notices(calendarId: String) async throws -> [CalendarNotice]
    func setStatus(calendarId: String, uid: String, status: MemberStatus) async throws
    func removeMember(calendarId: String, uid: String) async throws
    /// 自分の参加の状態を見張る。承認待ちの間、持ち主が承認したことがすぐ届く。参加者から外されたら nil。戻り値で見張りをやめる
    func listenMyStatus(calendarId: String, uid: String, onChange: @escaping (MemberStatus?) -> Void) -> () -> Void
    func updateMine(calendarId: String, uid: String, displayName: String, sharedKeys: [String], avatar: String,
                    shareManual: Bool) async throws
    /// 持ち主が、カレンダーの名前・アイコン・許可制を変える(招待に写してある分も合わせる)
    func updateCalendar(calendarId: String, uid: String, name: String, icon: String, requireApproval: Bool) async throws
    /// カレンダー本体の名前・アイコン・許可制を見張る(持ち主が変えたら、開いたままの端末にもすぐ届く)。戻り値で見張りをやめる
    func listenInfo(calendarId: String, onChange: @escaping (CalendarInfo) -> Void) -> () -> Void
}

/// カレンダー本体の、持ち主が変えられる項目
struct CalendarInfo: Equatable {
    var name: String
    var icon: String
    var requireApproval: Bool
}

/// 一覧にだけ残っていて、中ではもう参加者でなくなっていた共有カレンダー
struct GoneCalendar: Equatable {
    let name: String
    /// true なら、カレンダーが削除された。false なら、参加者から外された
    let deleted: Bool

    var text: String { "「" + name + "」" + (deleted ? "は削除されました" : "から外されました") }
}

extension CalendarBacking {
    func goneCalendars(uid: String) async -> [GoneCalendar] { [] }
    func addNotice(calendarId: String, kind: String, name: String, byUid: String) async throws {}
    func notices(calendarId: String) async throws -> [CalendarNotice] { [] }
    func listenInfo(calendarId: String, onChange: @escaping (CalendarInfo) -> Void) -> () -> Void { {} }
}

/// 共有カレンダーの、退会・削除のお知らせ 1 件
struct CalendarNotice: Equatable {
    let id: String
    /// "left"(自分で退会) / "removed"(外された)
    let kind: String
    let name: String
    let byUid: String
    let at: Double

    var text: String { name + (kind == "removed" ? "さんが外されました" : "さんが退会しました") }
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
    /// 承認待ちだった共有カレンダーが、承認されたとき(すぐ見られるようになった合図)
    @ObservationIgnored var onApproved: ((SharedCalendar) -> Void)?
    /// 参加していた共有カレンダーが削除された・外されたと分かったとき
    @ObservationIgnored var onGone: ((GoneCalendar) -> Void)?
    /// 共有カレンダーの名前・アイコン・許可制が変わったとき(開いている画面の見出しを合わせる)
    @ObservationIgnored var onInfoChange: ((SharedCalendar) -> Void)?
    /// ログイン中の自分
    var myUid: String? { uid }
    var errorMessage: String?

    private let backing: CalendarBacking
    private var uid: String?
    /// 承認待ちのカレンダーごとの、参加の状態の見張り
    @ObservationIgnored private var statusListeners: [String: () -> Void] = [:]
    /// 参加しているカレンダーごとの、名前・アイコンの見張り
    @ObservationIgnored private var infoListeners: [String: () -> Void] = [:]

    init(backing: CalendarBacking) {
        self.backing = backing
    }

    func start(uid: String) async {
        self.uid = uid
        calendars = []
        do {
            let list = try await backing.joined(uid: uid)
            guard self.uid == uid else { return }
            calendars = SharedCalendar.ordered(list)
            syncStatusListeners()
            onChange?()
            for g in await backing.goneCalendars(uid: uid) { onGone?(g) }
        } catch {
            // 取れなかったときは一覧が空のまま。ドロワーを開き直したときに取り直す
        }
    }

    func stop() {
        uid = nil
        calendars = []
        syncStatusListeners()
        onChange?()
    }

    /// 承認待ちのカレンダーだけ、参加の状態を見張る。承認されたら、すぐ見られるようにする(アプリを閉じなくてよい)
    private func syncStatusListeners() {
        syncInfoListeners()
        let waiting = Set(calendars.filter { $0.status == .pending }.map(\.id))
        for (id, stop) in statusListeners where uid == nil || !waiting.contains(id) {
            stop()
            statusListeners[id] = nil
        }
        guard let uid else { return }
        for id in waiting where statusListeners[id] == nil {
            statusListeners[id] = backing.listenMyStatus(calendarId: id, uid: uid) { [weak self] status in
                Task { @MainActor in self?.applyStatus(status, for: id) }
            }
        }
    }

    /// 参加している(承認済みの)カレンダーの、名前・アイコン・許可制を見張る。
    /// 持ち主が変えたとき、ほかの人の端末に、アプリを開き直さなくても届くようにする
    private func syncInfoListeners() {
        let active = Set(calendars.filter { $0.status == .active }.map(\.id))
        for (id, stop) in infoListeners where uid == nil || !active.contains(id) {
            stop()
            infoListeners[id] = nil
        }
        guard uid != nil else { return }
        for id in active where infoListeners[id] == nil {
            infoListeners[id] = backing.listenInfo(calendarId: id) { [weak self] info in
                Task { @MainActor in self?.applyInfo(info, for: id) }
            }
        }
    }

    private func applyInfo(_ info: CalendarInfo, for id: String) {
        guard let i = calendars.firstIndex(where: { $0.id == id }) else { return }
        let c = calendars[i]
        guard c.name != info.name || c.icon != info.icon || c.requireApproval != info.requireApproval else { return }
        calendars[i].name = info.name
        calendars[i].icon = info.icon
        calendars[i].requireApproval = info.requireApproval
        onInfoChange?(calendars[i])
    }

    private func applyStatus(_ status: MemberStatus?, for id: String) {
        guard let i = calendars.firstIndex(where: { $0.id == id }), calendars[i].status == .pending else { return }
        if status == .active {
            calendars[i].status = .active
            syncStatusListeners()
            onChange?()
            onApproved?(calendars[i])
        } else if status == nil {
            // 申し込みが却下された(参加者から外された)
            calendars.remove(at: i)
            syncStatusListeners()
            onChange?()
        }
    }

    /// 参加している共有カレンダーの一覧を取り直す(アプリに戻ったときなど)
    func refresh() async {
        guard let uid, let list = try? await backing.joined(uid: uid), self.uid == uid else { return }
        let before = Dictionary(calendars.map { ($0.id, $0.status) }, uniquingKeysWith: { a, _ in a })
        // 読めなかったカレンダーが一覧から消えないよう、取れた分だけ入れ替える(増えた分は足す)
        var merged = calendars
        for c in list {
            if let i = merged.firstIndex(where: { $0.id == c.id }) { merged[i] = c } else { merged.append(c) }
        }
        calendars = SharedCalendar.ordered(merged)
        syncStatusListeners()
        onChange?()
        for c in list { onInfoChange?(c) }
        for c in list where before[c.id] == .pending && c.status == .active { onApproved?(c) }
        for g in await backing.goneCalendars(uid: uid) { onGone?(g) }
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
            self.calendars = SharedCalendar.ordered(self.calendars + [made.calendar])
            self.syncStatusListeners()
            self.onChange?()
            return made
        }
    }

    /// ログインの引き継ぎが済んで、共有カレンダーの操作ができるか(起動直後は、まだのことがある)
    var isReady: Bool { uid != nil }

    /// アカウント登録の前に、招待された共有カレンダーの名前だけ調べる(失敗したら nil)
    func inviteName(code raw: String) async -> String? {
        guard let code = InviteCode.parse(raw), let p = try? await backing.preview(code: code), !p.calendarName.isEmpty else { return nil }
        return p.calendarName
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
    func join(code: InviteCode, displayName: String, sharedKeys: [String], avatar: String = "") async -> SharedCalendar? {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uid, !name.isEmpty else { return nil }
        if let existing = calendars.first(where: { $0.id == code.calendarId }) { return existing }
        return await run("参加できませんでした", invalid: "招待コードが無効か、期限が切れています") {
            var joined = try await self.backing.join(uid: uid, code: code, displayName: name, sharedKeys: sharedKeys, avatar: avatar)
            joined.mySharedKeys = joined.kind == .oneway ? [] : sharedKeys
            self.calendars = SharedCalendar.ordered(self.calendars + [joined])
            self.syncStatusListeners()
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

    /// カレンダーの設定・承認・参加者の削除・招待ができるか。見せるだけは持ち主、相互に共有は参加している全員
    func canManage(_ calendar: SharedCalendar) -> Bool {
        guard let uid, calendar.status == .active else { return false }
        return calendar.kind == .mutual || calendar.ownerUid == uid
    }

    /// 招待を作り直す。いまの QR コード・リンクは使えなくなる
    func reissueInvite(for calendar: SharedCalendar) async -> InviteCode? {
        guard let uid, canManage(calendar) else { return nil }
        return await run("招待を作り直せませんでした") {
            try await self.backing.reissueInvite(uid: uid, calendar: calendar)
        }
    }

    /// 退出する。相互に共有するカレンダーでは、最後の 1 人が退出すると、カレンダーごと消える。
    /// 残る人がいるときは、退会のお知らせを残す。見せるだけのカレンダーの持ち主は、退出できない(削除する)
    func leave(_ calendar: SharedCalendar) async {
        guard let uid, calendar.kind == .mutual || calendar.ownerUid != uid else { return }
        _ = await run("退出できませんでした") {
            if calendar.kind == .mutual, calendar.status == .active {
                let list = try await self.backing.members(calendarId: calendar.id)
                if !list.contains(where: { $0.id != uid && $0.status == .active }) {
                    try await self.backing.deleteCalendar(calendarId: calendar.id, uid: uid)
                } else {
                    let myName = list.first { $0.id == uid }?.displayName ?? ""
                    try? await self.backing.addNotice(calendarId: calendar.id, kind: "left", name: myName, byUid: uid)
                    try await self.backing.leave(uid: uid, calendarId: calendar.id)
                }
            } else {
                try await self.backing.leave(uid: uid, calendarId: calendar.id)
            }
            self.calendars.removeAll { $0.id == calendar.id }
            self.syncStatusListeners()
            self.onChange?()
        }
    }

    /// 共有カレンダーを消す(見せるだけの持ち主、または相互に共有する最後の 1 人)。参加者の画面からも消える
    func delete(_ calendar: SharedCalendar) async -> Bool {
        guard let uid, canManage(calendar) else { return false }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            try await backing.deleteCalendar(calendarId: calendar.id, uid: uid)
            calendars.removeAll { $0.id == calendar.id }
            syncStatusListeners()
            onChange?()
            return true
        } catch {
            // 原因が分かるように、元のエラーも添える
            errorMessage = "削除できませんでした\n\(error.localizedDescription)"
            return false
        }
    }

    /// まだ見ていない退会のお知らせ(自分のものは除く)。初めて開いたときは、昔のお知らせは出さない
    func takeNotices(for calendarId: String) async -> [String] {
        guard let uid, let list = try? await backing.notices(calendarId: calendarId) else { return [] }
        let key = "notice-seen-\(uid)-\(calendarId)"
        let now = (Date().timeIntervalSince1970 * 1000).rounded()
        let seen = UserDefaults.standard.object(forKey: key) as? Double
        UserDefaults.standard.set(max(seen ?? now, list.map(\.at).max() ?? 0, seen == nil ? now : 0), forKey: key)
        guard let seen else { return [] }
        return list.filter { $0.at > seen && $0.byUid != uid }.sorted { $0.at < $1.at }.map(\.text)
    }

    func members(of calendar: SharedCalendar) async -> [CalendarMember]? {
        await run("参加者を取得できませんでした") { try await self.backing.members(calendarId: calendar.id) }
    }

    /// 承認待ちの人を承認する
    func approve(_ member: CalendarMember, in calendar: SharedCalendar) async -> Bool {
        guard canManage(calendar) else { return false }
        return await run("承認できませんでした") {
            try await self.backing.setStatus(calendarId: calendar.id, uid: member.id, status: .active)
            return true
        } ?? false
    }

    /// 参加者を削除する(承認待ちの却下も同じ)。参加していた人なら、残った人へのお知らせを残す
    func remove(_ member: CalendarMember, from calendar: SharedCalendar) async -> Bool {
        guard let uid, canManage(calendar), member.id != uid else { return false }
        return await run("削除できませんでした") {
            if member.status == .active {
                try? await self.backing.addNotice(calendarId: calendar.id, kind: "removed", name: member.displayName, byUid: uid)
            }
            try await self.backing.removeMember(calendarId: calendar.id, uid: member.id)
            return true
        } ?? false
    }

    /// 持ち主が、カレンダーの名前・アイコン・許可制を変える。
    /// 許可制をやめるときは、申請中の人を全員承認してから切り替える(承認されないまま取り残されないように)
    func updateCalendar(_ calendar: SharedCalendar, name: String, icon: String, requireApproval: Bool) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uid, canManage(calendar), !trimmed.isEmpty else { return false }
        return await run("保存できませんでした") {
            if calendar.requireApproval && !requireApproval {
                let pending = try await self.backing.members(calendarId: calendar.id).filter { $0.status == .pending }
                for m in pending {
                    try await self.backing.setStatus(calendarId: calendar.id, uid: m.id, status: .active)
                }
            }
            try await self.backing.updateCalendar(calendarId: calendar.id, uid: uid, name: trimmed,
                                                  icon: CalendarIcon.resolved(icon), requireApproval: requireApproval)
            if let i = self.calendars.firstIndex(where: { $0.id == calendar.id }) {
                self.calendars[i].name = trimmed
                self.calendars[i].icon = CalendarIcon.resolved(icon)
                self.calendars[i].requireApproval = requireApproval
                self.onInfoChange?(self.calendars[i])
            }
            self.onChange?()
            return true
        } ?? false
    }

    /// 自分の共有者名と、共有に出す項目を変える
    /// shareManual: nil なら、いまの共有のしかたのまま
    func updateMine(in calendar: SharedCalendar, displayName: String, sharedKeys: [String], avatar: String = "",
                    shareManual: Bool? = nil) async -> Bool {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uid, !name.isEmpty else { return false }
        let manual = shareManual ?? calendar.myShareManual
        return await run("保存できませんでした") {
            try await self.backing.updateMine(calendarId: calendar.id, uid: uid, displayName: name, sharedKeys: sharedKeys,
                                              avatar: avatar, shareManual: manual)
            if let i = self.calendars.firstIndex(where: { $0.id == calendar.id }) {
                self.calendars[i].mySharedKeys = sharedKeys
                self.calendars[i].myShareManual = manual
            }
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
