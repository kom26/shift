import Foundation
import Observation

/// 共有カレンダーに載せる予定。公開できる項目だけ(給料・休憩・メモは入れない)
struct SharedEvent: Equatable, Identifiable {
    /// "<持ち主の uid>_<予定の ID>"
    let id: String
    let ownerUid: String
    /// 職場・ラベルのキー(ShareKey)
    let sourceKey: String
    let title: String
    let startDate: String
    let endDate: String
    let startTime: String?
    let endTime: String?
    let allDay: Bool
    /// 職場名またはラベル名
    let name: String
    let color: String
    /// 共有した人のカレンダーで、この予定のバーに時間を出しているか(受け取る側の初期の表示になる)
    var barTime: Bool = false
    /// 日付を決めた予定か。false は「未配置」(共有カレンダーの中で作った予定だけ。startDate・endDate は空)
    var placed: Bool = true
    /// 最後に変えた時刻(Unix ミリ秒)と、変えた人の名前。共有の予定の編集画面の下に出す(古い予定は nil)
    var updatedAt: Double? = nil
    var updatedByName: String? = nil
    /// メモ・URL・画像。共有カレンダーの中で作った予定だけが持つ(自分の予定を共有に出すときは、メモなどは出さない)。
    /// 画像の名前は `AttachmentStore.calendarPrefix` で始まり、共有カレンダーの保存先に置かれる
    var memo: String = ""
    var url: String = ""
    var imageId: String? = nil

    /// 共有カレンダーの中で作った予定のキー(参加者全員が直せる)
    static let calendarKey = "calendar"

    var isCalendarOwned: Bool { sourceKey == Self.calendarKey }

    /// 共有カレンダーの中で新しく作る予定。給料の項目は持たない
    static func newInCalendar(uid: String, date: String, color: String = EventLabel.noneColor) -> SharedEvent {
        SharedEvent(id: "cal_" + UUID().uuidString, ownerUid: uid, sourceKey: calendarKey, title: "",
                    startDate: date, endDate: date, startTime: nil, endTime: nil, allDay: true, name: "", color: color)
    }

    /// 編集画面の下に出す「最終変更」の文(記録がない予定は nil)
    func lastModifiedText(calendar: Calendar = .current) -> String? {
        guard let at = updatedAt else { return nil }
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: Date(timeIntervalSince1970: at / 1000))
        let when = String(format: "%d年%d月%d日 %d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
        let who = (updatedByName?.isEmpty == false) ? updatedByName! : "不明"
        return "- 最終変更\(when) ・\(who) -"
    }

    /// 日付を決めない予定(未配置)の下書き。あとで、カレンダーの日にドラッグして置く
    static func newUnplacedInCalendar(uid: String, color: String = EventLabel.noneColor) -> SharedEvent {
        var e = newInCalendar(uid: uid, date: "", color: color)
        e.placed = false
        return e
    }

    /// その日へ動かした予定(複数日の予定は、日数を保つ。未配置からは、時間があれば夜をまたぐ分を足す)
    func moved(to date: String) -> SharedEvent {
        var end = date
        if placed {
            end = Rules.addDays(date, max(0, Rules.daysBetween(startDate, endDate)))
        } else if !allDay, let st = startTime, let et = endTime {
            end = Rules.resolveEndDate(start: date, end: date, allDay: false, startTime: st, endTime: et) ?? date
        }
        var e = SharedEvent(id: id, ownerUid: ownerUid, sourceKey: sourceKey, title: title, startDate: date, endDate: end,
                            startTime: startTime, endTime: endTime, allDay: allDay, name: name, color: color, barTime: barTime)
        e.placed = true
        e.memo = memo
        e.url = url
        e.imageId = imageId
        return e
    }

    /// 未配置に戻した予定(日付を空にする。時間は残す)
    func unplaced() -> SharedEvent {
        var e = SharedEvent(id: id, ownerUid: ownerUid, sourceKey: sourceKey, title: title, startDate: "", endDate: "",
                            startTime: startTime, endTime: endTime, allDay: allDay, name: name, color: color, barTime: barTime)
        e.placed = false
        e.memo = memo
        e.url = url
        e.imageId = imageId
        return e
    }

    /// 共有に出せる予定ならコピーを作る(日付のある予定だけ)
    static func make(from e: ShiftEvent, uid: String, store: Store) -> SharedEvent? {
        guard e.placed, let start = e.startDate else { return nil }
        let workplace = store.workplace(for: e)
        return SharedEvent(id: "\(uid)_\(e.id)", ownerUid: uid, sourceKey: ShareKey.of(e, store: store),
                           title: e.title, startDate: start, endDate: e.endDate ?? start,
                           startTime: e.allDay ? nil : e.startTime, endTime: e.allDay ? nil : e.endTime,
                           allDay: e.allDay,
                           name: workplace?.name ?? store.label(for: e.labelId)?.name ?? "",
                           color: e.color, barTime: e.barShowsTime)
    }

    /// 共有カレンダーの画面で、同じカレンダー部品に表示するための予定(見るだけ)。バーはタイトルだけ
    /// showsTime: この端末で選んだ表示(true: 時間 / false: 予定名)。nil なら共有した人の表示に合わせる。
    /// 時間のない予定は、どちらでも予定名のまま
    func shiftEvent(color shownColor: String? = nil, showsTime: Bool? = nil) -> ShiftEvent {
        ShiftEvent(id: id, title: title, memo: memo, color: shownColor ?? color,
                   startDate: placed ? startDate : nil, endDate: placed ? endDate : nil,
                   placed: placed, allDay: allDay, startTime: startTime, endTime: endTime, workHours: nil,
                   barShowsTitle: (showsTime ?? barTime) ? nil : true, url: url.isEmpty ? nil : url, imageId: imageId)
    }
}

/// 共有カレンダーの予定のクラウド側(テストでは差し替える)
protocol SharedEventsBacking: AnyObject {
    func fetch(calendarId: String) async throws -> [SharedEvent]
    /// 予定が変わるたびに、全部の予定が届く。戻り値で購読をやめる
    func listen(calendarId: String, onChange: @escaping ([SharedEvent]) -> Void) -> () -> Void
    func set(calendarId: String, event: SharedEvent) async throws
    func delete(calendarId: String, id: String) async throws
    /// 自分が出した予定の ID
    func mineIds(calendarId: String, uid: String) async throws -> Set<String>
}

/// 手動共有で、確認を待っている変更 1 件
struct ShareChange: Identifiable, Equatable {
    enum Kind: Equatable { case added, changed, removed }

    let kind: Kind
    /// 追加・変更は、これから共有する内容。共有から消えるものは、いま共有されている内容
    let event: SharedEvent

    var id: String { event.id }
}

/// 自分の予定のうち、共有に出す職場・ラベルの予定を、参加している共有カレンダーに載せる。
/// 自動のカレンダーには、変わったところだけ送る(共有をやめた項目や、消した予定は、カレンダーからも消す)。
/// 手動のカレンダーには送らず、いまの共有との違いを「確認を待つ変更」として持つ。確認して許可した分だけ送る
@MainActor
@Observable
final class SharedPublisher {
    @ObservationIgnored private let backing: SharedEventsBacking
    @ObservationIgnored private weak var store: Store?
    @ObservationIgnored private let calendars: () -> [SharedCalendar]
    @ObservationIgnored private let uid: () -> String?
    /// カレンダーごとに、いま載せてある内容(送り直しを避ける)
    @ObservationIgnored private var pushed: [String: [String: SharedEvent]] = [:]
    /// 手動のカレンダーごとに、いま共有されている自分の予定(クラウドから一度読んで、送ったぶんだけ更新する)
    @ObservationIgnored private var remote: [String: [String: SharedEvent]] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let debounce: Duration

    /// 手動のカレンダーごとの、確認を待つ変更
    private(set) var pending: [String: [ShareChange]] = [:]

    init(backing: SharedEventsBacking, store: Store, debounce: Duration = .seconds(2),
         calendars: @escaping () -> [SharedCalendar], uid: @escaping () -> String?) {
        self.backing = backing
        self.store = store
        self.debounce = debounce
        self.calendars = calendars
        self.uid = uid
    }

    func pendingCount(for calendarId: String) -> Int { pending[calendarId]?.count ?? 0 }

    /// 予定や参加の状態が変わったとき。少し待って、まとめて載せる
    func schedule() {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.debounce)
            guard !Task.isCancelled else { return }
            await self.syncNow()
        }
    }

    func syncNow() async {
        guard let store, let uid = uid() else { return }
        let mine = calendars()
        // 抜けたカレンダーの記録は捨てる
        pushed = pushed.filter { id, _ in mine.contains { $0.id == id } }
        let manualIds = Set(mine.filter { $0.myShareManual && $0.canPublish(uid: uid) }.map(\.id))
        remote = remote.filter { manualIds.contains($0.key) }
        pending = pending.filter { manualIds.contains($0.key) }
        for cal in mine where cal.canPublish(uid: uid) {
            if cal.myShareManual {
                pushed[cal.id] = nil
                await refreshPending(for: cal, uid: uid, store: store)
            } else {
                await publish(to: cal, uid: uid, store: store)
            }
        }
    }

    /// 共有に出す予定(共有する勤務予定・ラベルに入っているもの)を、共有の形にしたもの
    private func desiredEvents(for cal: SharedCalendar, uid: String, store: Store) -> [String: SharedEvent] {
        let keys = Set(cal.mySharedKeys)
        var desired: [String: SharedEvent] = [:]
        for e in store.events {
            guard let shared = SharedEvent.make(from: e, uid: uid, store: store), keys.contains(shared.sourceKey) else { continue }
            desired[shared.id] = shared
        }
        return desired
    }

    private func publish(to cal: SharedCalendar, uid: String, store: Store) async {
        let desired = desiredEvents(for: cal, uid: uid, store: store)
        do {
            var current: [String: SharedEvent]
            if let known = pushed[cal.id] {
                current = known
            } else {
                // このアプリを開いて最初の 1 回は、クラウドに残っている自分の分を確かめて、不要なものを消す
                let remote = try await backing.mineIds(calendarId: cal.id, uid: uid)
                for id in remote where id.hasPrefix(uid + "_") && desired[id] == nil {
                    try await backing.delete(calendarId: cal.id, id: id)
                }
                current = [:]
            }
            for (id, e) in desired where current[id] != e {
                try await backing.set(calendarId: cal.id, event: e)
                current[id] = e
            }
            for id in current.keys where desired[id] == nil {
                try await backing.delete(calendarId: cal.id, id: id)
                current[id] = nil
            }
            pushed[cal.id] = current
        } catch {
            // 送れなかったときは、次の変更か起動でやり直す(記録は更新しない)
        }
    }

    // MARK: 手動共有

    /// いま共有されている自分の予定を、クラウドから読んでおく(共有カレンダーの中で作った予定は除く)
    private func loadRemote(for cal: SharedCalendar, uid: String) async -> [String: SharedEvent]? {
        if let known = remote[cal.id] { return known }
        guard let all = try? await backing.fetch(calendarId: cal.id) else { return nil }
        let mine = all.filter { $0.ownerUid == uid && !$0.isCalendarOwned }
        let loaded = Dictionary(mine.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        remote[cal.id] = loaded
        return loaded
    }

    private func refreshPending(for cal: SharedCalendar, uid: String, store: Store) async {
        guard let current = await loadRemote(for: cal, uid: uid) else { return }
        pending[cal.id] = Self.changes(desired: desiredEvents(for: cal, uid: uid, store: store), remote: current)
    }

    /// いま共有されている内容と、共有するはずの内容の違い。開始日の順に並べる
    static func changes(desired: [String: SharedEvent], remote: [String: SharedEvent]) -> [ShareChange] {
        var list: [ShareChange] = []
        for (id, e) in desired {
            if let old = remote[id] {
                if old != e { list.append(ShareChange(kind: .changed, event: e)) }
            } else {
                list.append(ShareChange(kind: .added, event: e))
            }
        }
        for (id, old) in remote where desired[id] == nil {
            list.append(ShareChange(kind: .removed, event: old))
        }
        return list.sorted { ($0.event.startDate, $0.event.id) < ($1.event.startDate, $1.event.id) }
    }

    /// 確認して許可した変更だけを共有に送る。許可しなかった分は、確認を待つ変更に残る
    @discardableResult
    func share(_ changes: [ShareChange], in cal: SharedCalendar) async -> Bool {
        guard let store, let uid = uid(), cal.canPublish(uid: uid) else { return false }
        guard var current = await loadRemote(for: cal, uid: uid) else { return false }
        do {
            for change in changes {
                switch change.kind {
                case .added, .changed:
                    try await backing.set(calendarId: cal.id, event: change.event)
                    current[change.id] = change.event
                case .removed:
                    try await backing.delete(calendarId: cal.id, id: change.id)
                    current[change.id] = nil
                }
            }
            remote[cal.id] = current
            pending[cal.id] = Self.changes(desired: desiredEvents(for: cal, uid: uid, store: store), remote: current)
            return true
        } catch {
            // 途中で止まったときは、いまの状態を読み直す
            remote[cal.id] = nil
            await refreshPending(for: cal, uid: uid, store: store)
            return false
        }
    }
}

/// 共有カレンダーを開いている間の表示。参加者の予定を 1 つのカレンダーに重ねる。
/// ほかの人の予定は見るだけで、共有カレンダーの中で作った予定だけ直せる。予定は変わるたびに自動で更新される
@MainActor
@Observable
final class SharedViewState {
    private(set) var calendar: SharedCalendar?
    /// 表示用の入れ物。自分のデータとは別なので、ここでどう動かしても自分の予定は変わらない
    private(set) var store: Store?
    private(set) var loading = false
    private(set) var failed = false
    /// いま表示している予定(ID から引ける)
    private(set) var items: [String: SharedEvent] = [:]
    /// 参加者の名前(uid から引ける)
    private(set) var names: [String: String] = [:]
    /// この端末だけで効く、共有カレンダー上の職場・ラベルの色(キーは colorKey)
    private(set) var overrides: [String: String] = [:]
    /// この端末だけで効く、バーの表示の選び方(キーは colorKey。true: 時間 / false: 予定名)。ないものは共有した人の表示に合わせる
    private(set) var timeModes: [String: Bool] = [:]

    @ObservationIgnored private let events: SharedEventsBacking
    @ObservationIgnored private let calendars: CalendarService
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var unlisten: (() -> Void)?
    @ObservationIgnored private var latest: [SharedEvent] = []
    /// 共有カレンダーの誕生日・記念日の保存先(なければ、誕生日・記念日は共有されない)
    @ObservationIgnored var anniversaryBacking: SharedAnniversariesBacking?
    @ObservationIgnored private var unlistenAnniversaries: (() -> Void)?
    @ObservationIgnored private var latestAnniversaries: [SharedAnniversary] = []
    /// 開いている共有カレンダーの誕生日・記念日を入れた人(ID から引ける)
    private(set) var anniversaryOwners: [String: String] = [:]
    /// 開いている共有カレンダーの背景(共有者で共通)
    private(set) var background = ""
    @ObservationIgnored private var unlistenBackground: (() -> Void)?

    /// 参加者のアバター(uid から引ける。空は頭文字)
    private(set) var avatars: [String: String] = [:]

    /// 自分のカレンダーに重ねている共有カレンダー
    private(set) var overlayIds: Set<String>
    /// 重ねている予定(ID から引ける)
    private(set) var overlayItems: [String: SharedEvent] = [:]
    @ObservationIgnored private weak var mainStore: Store?
    @ObservationIgnored private var overlayListeners: [String: () -> Void] = [:]
    @ObservationIgnored private var overlayLatest: [String: [SharedEvent]] = [:]
    /// 重ねている予定が、どの共有カレンダーのものか
    @ObservationIgnored private var overlayCalendarOf: [String: String] = [:]
    /// 重ねている共有カレンダーごとの、参加者(uid から引ける)
    @ObservationIgnored private var overlayMembers: [String: [String: CalendarMember]] = [:]

    private static let overridesKey = "shared-color-overrides"
    private static let overlayKey = "shared-overlay-ids"
    private static let timeModesKey = "shared-bar-time-modes"

    init(events: SharedEventsBacking, calendars: CalendarService, defaults: UserDefaults = .standard) {
        self.events = events
        self.calendars = calendars
        self.defaults = defaults
        overlayIds = Set(defaults.stringArray(forKey: Self.overlayKey) ?? [])
    }

    /// 重ねた予定を入れる、自分の予定の入れ物
    func attach(store: Store) {
        mainStore = store
        rebuildOverlay()
    }

    var isOpen: Bool { calendar != nil }

    /// このカレンダーの中に予定を作れるか。見せるだけのカレンダーでは、持ち主だけ
    var canCreate: Bool { canWrite(in: calendar) }

    private func canWrite(in c: SharedCalendar?) -> Bool {
        guard let c, let uid = calendars.myUid else { return false }
        return c.status == .active && (c.kind == .mutual || c.ownerUid == uid)
    }

    /// その予定がある共有カレンダー(開いているものか、重ねているもの)
    private func calendarOf(_ id: String) -> SharedCalendar? {
        if items[id] != nil { return calendar }
        guard let cid = overlayCalendarOf[id] else { return nil }
        return calendars.calendars.first { $0.id == cid }
    }

    func isEditable(_ id: String) -> Bool { event(id)?.isCalendarOwned == true && canWrite(in: calendarOf(id)) }

    /// ドラッグで動かせるか。共有カレンダーの中で作った予定と、共有に出した自分の予定(ほかの人の予定は動かせない)
    func canDrag(_ id: String) -> Bool { isEditable(id) || ownEventId(for: id) != nil }

    // MARK: 共有に出した自分の予定(共有カレンダーの中でも、自分の予定として直せる・動かせる)

    /// 共有に出した自分の予定の、自分のカレンダーでの ID。そうでなければ nil
    /// (共有カレンダー上の ID は、"<自分の uid>_<予定の ID>")
    func ownEventId(for id: String) -> String? {
        guard let e = event(id), !e.isCalendarOwned, let uid = calendars.myUid, e.ownerUid == uid else { return nil }
        let prefix = uid + "_"
        guard id.hasPrefix(prefix) else { return nil }
        let own = String(id.dropFirst(prefix.count))
        return mainStore?.events.contains { $0.id == own } == true ? own : nil
    }

    /// 共有に出した自分の予定の、自分のカレンダーでの予定
    func ownEvent(for id: String) -> ShiftEvent? {
        guard let own = ownEventId(for: id) else { return nil }
        return mainStore?.events.first { $0.id == own }
    }

    func placeOwn(id: String, on date: String) {
        if let own = ownEventId(for: id) { mainStore?.place(id: own, on: date) }
    }

    func copyOwn(id: String, on date: String) {
        if let own = ownEventId(for: id) { mainStore?.copy(id: own, to: [date]) }
    }

    func unplaceOwn(id: String) {
        if let own = ownEventId(for: id) { mainStore?.unplace(id: own) }
    }

    func deleteOwn(id: String) {
        if let own = ownEventId(for: id) { mainStore?.delete(id: own) }
    }

    /// その日へ動かす(未配置の予定は、その日に置く)
    @discardableResult
    func place(id: String, on date: String) async -> Bool {
        guard isEditable(id), let e = event(id) else { return false }
        return await save(e.moved(to: date))
    }

    /// 未配置に戻す
    @discardableResult
    func unplace(id: String) async -> Bool {
        guard isEditable(id), let e = event(id) else { return false }
        return await save(e.unplaced())
    }

    /// その日へコピーする(新しい予定として足す。元の予定は、そのまま)
    @discardableResult
    func copy(id: String, on date: String) async -> Bool {
        guard isEditable(id), let e = event(id), let uid = calendars.myUid else { return false }
        var made = SharedEvent(id: "cal_" + UUID().uuidString, ownerUid: uid, sourceKey: SharedEvent.calendarKey,
                               title: e.title, startDate: e.startDate, endDate: e.endDate, startTime: e.startTime,
                               endTime: e.endTime, allDay: e.allDay, name: e.name, color: e.color, barTime: e.barTime)
        made.placed = e.placed
        // 画像は、共有カレンダーの同じ保存先を指す(コピーは、同じ画像を見る)
        made.memo = e.memo
        made.url = e.url
        made.imageId = e.imageId
        return await save(made.moved(to: date))
    }

    /// 予定を作れる共有カレンダー(予定の保存先に選べるもの)
    func writableCalendars() -> [SharedCalendar] {
        calendars.calendars.filter { canWrite(in: $0) }
    }

    /// その予定がある共有カレンダーの ID(開いているものか、重ねているもの)
    func calendarId(of eventId: String) -> String? { calendarOf(eventId)?.id }

    /// 保存先を切り替えるときの、共有の予定の下書き(新しい ID。中身は、あとで入れる)
    func newDraft() -> SharedEvent? {
        guard let uid = calendars.myUid else { return nil }
        return SharedEvent.newUnplacedInCalendar(uid: uid)
    }

    /// 日付を決めない予定の下書き
    func newUnplacedEvent() -> SharedEvent? {
        guard canCreate, let uid = calendars.myUid else { return nil }
        return SharedEvent.newUnplacedInCalendar(uid: uid)
    }

    func event(_ id: String) -> SharedEvent? { items[id] ?? overlayItems[id] }

    /// 予定をつくった人(日の一覧のアバター用)
    func owner(of id: String) -> (uid: String, name: String, avatar: String)? {
        guard let e = event(id) else { return nil }
        if items[id] != nil { return (e.ownerUid, names[e.ownerUid] ?? "", avatars[e.ownerUid] ?? "") }
        let m = overlayCalendarOf[id].flatMap { overlayMembers[$0]?[e.ownerUid] }
        return (e.ownerUid, m?.displayName ?? "", m?.avatar ?? "")
    }

    /// 新しい予定の下書き
    func newEvent(on date: String) -> SharedEvent? {
        guard canCreate, let uid = calendars.myUid else { return nil }
        return SharedEvent.newInCalendar(uid: uid, date: date)
    }

    func open(_ cal: SharedCalendar) async {
        close()
        calendar = cal
        overrides = Self.loadOverrides(defaults: defaults)[cal.id] ?? [:]
        timeModes = Self.loadTimeModes(defaults: defaults)[cal.id] ?? [:]
        store = Self.makeStore(events: [], overrides: [:])
        loading = true
        await loadNames()
        // 予定が変わるたびに届く(最初の 1 回も、ここから届く)
        unlisten = events.listen(calendarId: cal.id) { [weak self] list in
            Task { @MainActor in self?.apply(list, for: cal.id) }
        }
        unlistenAnniversaries = anniversaryBacking?.listenAnniversaries(calendarId: cal.id) { [weak self] list in
            Task { @MainActor in self?.applyAnniversaries(list, for: cal.id) }
        }
        unlistenBackground = anniversaryBacking?.listenBackground(calendarId: cal.id) { [weak self] key in
            Task { @MainActor in
                if self?.calendar?.id == cal.id { self?.background = key }
            }
        }
        await refresh()
    }

    func close() {
        unlisten?()
        unlisten = nil
        unlistenAnniversaries?()
        unlistenAnniversaries = nil
        unlistenBackground?()
        unlistenBackground = nil
        background = ""
        latestAnniversaries = []
        anniversaryOwners = [:]
        calendar = nil
        store = nil
        items = [:]
        latest = []
        failed = false
        loading = false
    }

    /// 手動の更新と、アプリに戻ったときの取り直し
    func refresh() async {
        guard let cal = calendar else { return }
        loading = true
        failed = false
        defer { loading = false }
        do {
            let list = try await events.fetch(calendarId: cal.id)
            apply(list, for: cal.id)
        } catch {
            failed = true
        }
    }

    /// 共有カレンダーの中の予定を保存する(表示は自動で更新される)
    func save(_ e: SharedEvent) async -> Bool {
        await save(e, in: calendarOf(e.id) ?? calendar)
    }

    /// 開いていない共有カレンダーにも、予定を保存する(自分のカレンダーや別の共有カレンダーから、移すとき)
    func save(_ e: SharedEvent, inCalendar id: String) async -> Bool {
        await save(e, in: calendars.calendars.first { $0.id == id })
    }

    private func save(_ e: SharedEvent, in target: SharedCalendar?) async -> Bool {
        guard let cal = target, canWrite(in: cal), e.isCalendarOwned else { return false }
        // 変えた人と時刻を記録する(編集画面の下の「最終変更」)
        var stamped = e
        stamped.updatedAt = Date().timeIntervalSince1970 * 1000
        stamped.updatedByName = calendars.myUid.flatMap { names[$0] }
        do {
            try await events.set(calendarId: cal.id, event: stamped)
            return true
        } catch {
            return false
        }
    }

    func delete(id: String) async -> Bool {
        guard let cal = calendarOf(id), isEditable(id) else { return false }
        do {
            try await events.delete(calendarId: cal.id, id: id)
            return true
        } catch {
            return false
        }
    }

    // MARK: 色(この端末の、共有カレンダー上だけ)

    /// 色を変える単位。ほかの人の職場・ラベルは、持ち主ごとに別。共有カレンダーの中で作った予定は 1 つにまとまる
    static func colorKey(for e: SharedEvent) -> String {
        e.isCalendarOwned ? SharedEvent.calendarKey : "\(e.ownerUid)|\(e.sourceKey)"
    }

    /// 共有カレンダー上での、その予定の職場・ラベルの色
    func color(for e: SharedEvent) -> String { overrideMap(for: e)[Self.colorKey(for: e)] ?? e.color }

    private func overrideMap(for e: SharedEvent) -> [String: String] {
        if calendar != nil, items[e.id] != nil { return overrides }
        if let cid = overlayCalendarOf[e.id] { return Self.loadOverrides(defaults: defaults)[cid] ?? [:] }
        return overrides
    }

    /// 色を変える。nil で元の色に戻す
    func setColor(_ color: String?, for e: SharedEvent) {
        let key = Self.colorKey(for: e)
        let inOpen = calendar != nil && items[e.id] != nil
        guard let cid = inOpen ? calendar?.id : overlayCalendarOf[e.id] else { return }
        var all = Self.loadOverrides(defaults: defaults)
        var map = all[cid] ?? [:]
        if let color { map[key] = color } else { map[key] = nil }
        all[cid] = map
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: Self.overridesKey) }
        if inOpen {
            overrides = map
            rebuild()
        }
        rebuildOverlay()
    }

    // MARK: バーの表示(予定名 / 時間。この端末の、共有カレンダー上だけ)

    /// 共有カレンダー上で選んだ表示(true: 時間 / false: 予定名)。nil は、共有した人の表示に合わせる
    func showsTime(for e: SharedEvent) -> Bool? { timeModesMap(for: e)[Self.colorKey(for: e)] }

    private func timeModesMap(for e: SharedEvent) -> [String: Bool] {
        if calendar != nil, items[e.id] != nil { return timeModes }
        if let cid = overlayCalendarOf[e.id] { return Self.loadTimeModes(defaults: defaults)[cid] ?? [:] }
        return timeModes
    }

    /// バーに出すものを変える(nil で共有した人の表示に戻す)。色と同じ単位(持ち主ごとの職場・ラベル)で変わる
    func setShowsTime(_ on: Bool?, for e: SharedEvent) {
        let key = Self.colorKey(for: e)
        let inOpen = calendar != nil && items[e.id] != nil
        guard let cid = inOpen ? calendar?.id : overlayCalendarOf[e.id] else { return }
        var all = Self.loadTimeModes(defaults: defaults)
        var modes = all[cid] ?? [:]
        modes[key] = on
        all[cid] = modes
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: Self.timeModesKey) }
        if inOpen {
            timeModes = modes
            rebuild()
        }
        rebuildOverlay()
    }

    private static func loadTimeModes(defaults: UserDefaults) -> [String: [String: Bool]] {
        defaults.data(forKey: timeModesKey).flatMap { try? JSONDecoder().decode([String: [String: Bool]].self, from: $0) } ?? [:]
    }

    // MARK: 自分のカレンダーに重ねる

    func isOverlaid(_ id: String) -> Bool { overlayIds.contains(id) }

    /// 実際に重なっている共有カレンダーがあるか(退出・削除したカレンダーの古い記録は数えない)
    var isOverlaying: Bool {
        calendars.calendars.contains { $0.status == .active && overlayIds.contains($0.id) }
    }

    /// 共有カレンダーを重ねる・外す
    func setOverlay(_ ids: [String], on: Bool) {
        if on { overlayIds.formUnion(ids) } else { overlayIds.subtract(ids) }
        defaults.set(overlayIds.sorted(), forKey: Self.overlayKey)
        syncOverlay()
    }

    /// 参加している共有カレンダーの一覧が変わったとき、重ねる対象と購読をそろえる
    func syncOverlay() {
        let active = calendars.calendars.filter { $0.status == .active && overlayIds.contains($0.id) }
        let want = Set(active.map(\.id))
        for (id, stop) in overlayListeners where !want.contains(id) {
            stop()
            overlayListeners[id] = nil
            overlayLatest[id] = nil
            overlayMembers[id] = nil
        }
        for cal in active where overlayListeners[cal.id] == nil {
            let cid = cal.id
            overlayListeners[cid] = events.listen(calendarId: cid) { [weak self] list in
                Task { @MainActor in self?.applyOverlay(list, for: cid) }
            }
            Task { await loadOverlayMembers(cid) }
        }
        rebuildOverlay()
    }

    private func loadOverlayMembers(_ cid: String) async {
        guard let cal = calendars.calendars.first(where: { $0.id == cid }) else { return }
        let members = await calendars.members(of: cal) ?? []
        guard overlayListeners[cid] != nil else { return }
        overlayMembers[cid] = Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func applyOverlay(_ list: [SharedEvent], for cid: String) {
        guard overlayListeners[cid] != nil else { return }
        overlayLatest[cid] = list
        rebuildOverlay()
        if list.contains(where: { overlayMembers[cid]?[$0.ownerUid] == nil }) {
            Task { await loadOverlayMembers(cid) }
        }
    }

    /// 重ねる予定を組み立てて、自分の入れ物に渡す。自分が共有に出した予定(コピー)は、元の予定がすでに出ているので除く。
    /// 同じ予定が複数のカレンダーにあっても 1 つだけ出す
    private func rebuildOverlay() {
        let me = calendars.myUid
        var seen = Set<String>()
        var items: [String: SharedEvent] = [:]
        var owners: [String: String] = [:]
        var shown: [ShiftEvent] = []
        let saved = Self.loadOverrides(defaults: defaults)
        let savedTime = Self.loadTimeModes(defaults: defaults)
        for cid in overlayListeners.keys.sorted() {
            let map = saved[cid] ?? [:]
            let modes = savedTime[cid] ?? [:]
            for e in overlayLatest[cid] ?? [] {
                // 日付のない予定(未配置)は、重ねない
                if !e.placed { continue }
                if !e.isCalendarOwned, let me, e.ownerUid == me { continue }
                guard seen.insert(e.id).inserted else { continue }
                items[e.id] = e
                owners[e.id] = cid
                shown.append(e.shiftEvent(color: map[Self.colorKey(for: e)] ?? e.color,
                                          showsTime: modes[Self.colorKey(for: e)]))
            }
        }
        overlayItems = items
        overlayCalendarOf = owners
        mainStore?.setOverlay(shown)
    }

    private static func loadOverrides(defaults: UserDefaults) -> [String: [String: String]] {
        defaults.data(forKey: overridesKey).flatMap { try? JSONDecoder().decode([String: [String: String]].self, from: $0) } ?? [:]
    }

    // MARK: 内部

    private func loadNames() async {
        guard let cal = calendar else { return }
        let members = await calendars.members(of: cal) ?? []
        guard calendar?.id == cal.id else { return }
        names = Dictionary(members.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        avatars = Dictionary(members.map { ($0.id, $0.avatar) }, uniquingKeysWith: { a, _ in a })
    }

    private func apply(_ list: [SharedEvent], for id: String) {
        guard calendar?.id == id else { return }
        latest = list
        items = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        loading = false
        rebuild()
        // 名前を知らない参加者の予定が届いたら、参加者を取り直す
        if list.contains(where: { names[$0.ownerUid] == nil }) {
            Task { await loadNames() }
        }
    }

    private func rebuild() {
        store = Self.makeStore(events: latest, overrides: overrides, timeModes: timeModes,
                               anniversaries: latestAnniversaries.map(\.anniversary))
    }

    private func applyAnniversaries(_ list: [SharedAnniversary], for id: String) {
        guard calendar?.id == id else { return }
        latestAnniversaries = list
        anniversaryOwners = Dictionary(list.map { ($0.id, $0.ownerUid) }, uniquingKeysWith: { a, _ in a })
        rebuild()
    }

    // MARK: 誕生日・記念日

    /// 誕生日・記念日を直せるか。共有カレンダーに書ける人なら、だれが入れたものでも直せる・消せる
    var myUid: String? { calendars.myUid }

    func canEditAnniversary(_ id: String) -> Bool {
        anniversaryOwners[id] != nil && canCreate
    }

    // MARK: 背景

    /// その共有カレンダーの背景(開いていれば、いま見えているもの)
    func backgroundKey(of cid: String) async -> String {
        if calendar?.id == cid { return background }
        return (try? await anniversaryBacking?.fetchBackground(calendarId: cid)) ?? ""
    }

    /// 背景を変える(変えられるのは持ち主だけ)
    @discardableResult
    func setBackground(_ key: String, in cid: String) async -> Bool {
        guard let b = anniversaryBacking,
              calendars.calendars.first(where: { $0.id == cid })?.ownerUid == calendars.myUid else { return false }
        do {
            try await b.setBackground(calendarId: cid, key: key)
            if calendar?.id == cid { background = key }
            return true
        } catch {
            return false
        }
    }

    func anniversaries(in cid: String) async -> [SharedAnniversary]? {
        guard let b = anniversaryBacking else { return [] }
        return try? await b.fetchAnniversaries(calendarId: cid)
    }

    /// 誕生日・記念日を共有カレンダーに保存する(自分のアカウントの誕生日と連動しているものは、連動したまま)
    @discardableResult
    func saveAnniversary(_ a: Anniversary, in cid: String, ownerUid: String? = nil) async -> Bool {
        guard let uid = calendars.myUid, let b = anniversaryBacking else { return false }
        do {
            // 入れた人はそのまま(ほかの人が直しても変わらない)
            try await b.setAnniversary(calendarId: cid, SharedAnniversary(from: a, ownerUid: ownerUid ?? uid, linked: a.isAccountBirthday))
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func removeAnniversary(id: String, in cid: String) async -> Bool {
        guard let b = anniversaryBacking else { return false }
        do {
            try await b.deleteAnniversary(calendarId: cid, id: id)
            return true
        } catch {
            return false
        }
    }

    /// アカウントの誕生日を、共有カレンダーに追加する(1 人 1 件。アイコンと色は、アカウントのものから始める)
    @discardableResult
    func addMyBirthday(_ mine: Anniversary, name: String, in cid: String) async -> Bool {
        guard let uid = calendars.myUid else { return false }
        var a = mine
        a.id = SharedAnniversary.linkedId(uid: uid)
        // 名前は、この共有カレンダーで相手に見える名前を使う
        let shown = name.trimmingCharacters(in: .whitespaces)
        if !shown.isEmpty { a.name = shown + "の誕生日" }
        a.isMine = true
        return await saveAnniversary(a, in: cid)
    }

    /// アカウント設定の誕生日が変わったとき、連動して入れてある共有カレンダーの分も合わせる(登録をやめたら、消す)
    func syncMyBirthday(_ mine: Anniversary?) async {
        guard let uid = calendars.myUid, anniversaryBacking != nil else { return }
        let id = SharedAnniversary.linkedId(uid: uid)
        for cal in calendars.calendars where cal.status == .active {
            guard let list = await anniversaries(in: cal.id), let old = list.first(where: { $0.id == id }) else { continue }
            if var a = mine {
                // 日付だけ合わせる(名前は、この共有カレンダーで相手に見える名前)。選んだアイコンと色は、そのまま
                a.id = id
                a.isMine = true
                if let shown = await calendars.members(of: cal)?.first(where: { $0.id == uid })?.displayName,
                   !shown.trimmingCharacters(in: .whitespaces).isEmpty {
                    a.name = shown + "の誕生日"
                }
                var next = SharedAnniversary(from: a, ownerUid: uid, linked: true)
                next.icon = old.icon
                next.color = old.color
                next.memo = old.memo
                if next != old, let b = anniversaryBacking { try? await b.setAnniversary(calendarId: cal.id, next) }
            } else {
                await removeAnniversary(id: id, in: cal.id)
            }
        }
    }

    /// 退出するとき、アカウントと連動している自分の誕生日だけ消す(ほかの誕生日・記念日は残る)
    /// ウィジェットに渡すために、共有カレンダーの予定と誕生日・記念日を取ってくる(取れなければ nil)
    func widgetSnapshot(of calendar: SharedCalendar) async -> WidgetSharedCalendar? {
        guard let list = try? await events.fetch(calendarId: calendar.id) else { return nil }
        let annivs = (try? await anniversaryBacking?.fetchAnniversaries(calendarId: calendar.id)) ?? []
        let members = await calendars.members(of: calendar) ?? []
        return WidgetSharedCalendar(id: calendar.id, name: calendar.name, icon: calendar.icon,
                                    events: list.map { $0.shiftEvent() }, anniversaries: annivs.map(\.anniversary),
                                    sharedWorkplaceIds: calendar.mySharedKeys.filter { $0.hasPrefix("w:") }.map { String($0.dropFirst(2)) },
                                    eventOwners: Dictionary(list.filter { !$0.isCalendarOwned }.map { ($0.id, $0.ownerUid) }, uniquingKeysWith: { a, _ in a }),
                                    members: Dictionary(members.map { ($0.id, WidgetMember(name: $0.displayName, avatar: $0.avatar)) },
                                                        uniquingKeysWith: { a, _ in a }))
    }

    func removeMyLinkedBirthday(in cid: String) async {
        guard let uid = calendars.myUid else { return }
        await removeAnniversary(id: SharedAnniversary.linkedId(uid: uid), in: cid)
    }

    /// 参加者の予定から、表示用の入れ物を組み立てる。バーはタイトルだけ(誰の予定かは日の一覧のアバターで見せる)。
    /// 色は、この端末で変えていればそれを使う
    static func makeStore(events: [SharedEvent], overrides: [String: String], timeModes: [String: Bool] = [:],
                          anniversaries: [Anniversary] = []) -> Store {
        let name = "shared-" + UUID().uuidString
        let store = Store(fileURL: FileManager.default.temporaryDirectory.appending(path: name + ".json"),
                          defaults: UserDefaults(suiteName: name) ?? .standard)
        let list = events.map {
            $0.shiftEvent(color: overrides[colorKey(for: $0)] ?? $0.color, showsTime: timeModes[colorKey(for: $0)])
        }
        store.applySnapshot(SyncSnapshot(events: list, workplaces: [], favorites: [], customColors: [], hiddenSuggestions: []))
        anniversaries.forEach { store.saveAnniversary($0) }
        return store
    }
}
