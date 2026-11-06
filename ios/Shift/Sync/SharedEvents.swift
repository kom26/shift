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

    /// 共有カレンダーの中で作った予定のキー(参加者全員が直せる)
    static let calendarKey = "calendar"

    var isCalendarOwned: Bool { sourceKey == Self.calendarKey }

    /// 共有カレンダーの中で新しく作る予定。給料の項目は持たない
    static func newInCalendar(uid: String, date: String, color: String = EventLabel.noneColor) -> SharedEvent {
        SharedEvent(id: "cal_" + UUID().uuidString, ownerUid: uid, sourceKey: calendarKey, title: "",
                    startDate: date, endDate: date, startTime: nil, endTime: nil, allDay: true, name: "", color: color)
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
        ShiftEvent(id: id, title: title, memo: "", color: shownColor ?? color, startDate: startDate, endDate: endDate,
                   placed: true, allDay: allDay, startTime: startTime, endTime: endTime, workHours: nil,
                   barShowsTitle: (showsTime ?? barTime) ? nil : true)
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
        await refresh()
    }

    func close() {
        unlisten?()
        unlisten = nil
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
        guard let cal = calendarOf(e.id) ?? calendar, canWrite(in: cal), e.isCalendarOwned else { return false }
        do {
            try await events.set(calendarId: cal.id, event: e)
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
        store = Self.makeStore(events: latest, overrides: overrides, timeModes: timeModes)
    }

    /// 参加者の予定から、表示用の入れ物を組み立てる。バーはタイトルだけ(誰の予定かは日の一覧のアバターで見せる)。
    /// 色は、この端末で変えていればそれを使う
    static func makeStore(events: [SharedEvent], overrides: [String: String], timeModes: [String: Bool] = [:]) -> Store {
        let name = "shared-" + UUID().uuidString
        let store = Store(fileURL: FileManager.default.temporaryDirectory.appending(path: name + ".json"),
                          defaults: UserDefaults(suiteName: name) ?? .standard)
        let list = events.map {
            $0.shiftEvent(color: overrides[colorKey(for: $0)] ?? $0.color, showsTime: timeModes[colorKey(for: $0)])
        }
        store.applySnapshot(SyncSnapshot(events: list, workplaces: [], favorites: [], customColors: [], hiddenSuggestions: []))
        return store
    }
}
