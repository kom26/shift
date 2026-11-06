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
                           color: e.color)
    }

    /// 共有カレンダーの画面で、同じカレンダー部品に表示するための予定(見るだけ)。バーはタイトルだけ
    func shiftEvent(color shownColor: String? = nil) -> ShiftEvent {
        ShiftEvent(id: id, title: title, memo: "", color: shownColor ?? color, startDate: startDate, endDate: endDate,
                   placed: true, allDay: allDay, startTime: startTime, endTime: endTime, workHours: nil,
                   barShowsTitle: true)
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

/// 自分の予定のうち、共有に出す職場・ラベルの予定を、参加している共有カレンダーに載せる。
/// 変わったところだけ送る。共有をやめた項目や、消した予定は、カレンダーからも消す
@MainActor
final class SharedPublisher {
    private let backing: SharedEventsBacking
    private weak var store: Store?
    private let calendars: () -> [SharedCalendar]
    private let uid: () -> String?
    /// カレンダーごとに、いま載せてある内容(送り直しを避ける)
    private var pushed: [String: [String: SharedEvent]] = [:]
    private var task: Task<Void, Never>?
    private let debounce: Duration

    init(backing: SharedEventsBacking, store: Store, debounce: Duration = .seconds(2),
         calendars: @escaping () -> [SharedCalendar], uid: @escaping () -> String?) {
        self.backing = backing
        self.store = store
        self.debounce = debounce
        self.calendars = calendars
        self.uid = uid
    }

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
        for cal in mine where cal.canPublish(uid: uid) {
            await publish(to: cal, uid: uid, store: store)
        }
    }

    private func publish(to cal: SharedCalendar, uid: String, store: Store) async {
        let keys = Set(cal.mySharedKeys)
        var desired: [String: SharedEvent] = [:]
        for e in store.events {
            guard let shared = SharedEvent.make(from: e, uid: uid, store: store), keys.contains(shared.sourceKey) else { continue }
            desired[shared.id] = shared
        }
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
        for cid in overlayListeners.keys.sorted() {
            let map = saved[cid] ?? [:]
            for e in overlayLatest[cid] ?? [] {
                if !e.isCalendarOwned, let me, e.ownerUid == me { continue }
                guard seen.insert(e.id).inserted else { continue }
                items[e.id] = e
                owners[e.id] = cid
                shown.append(e.shiftEvent(color: map[Self.colorKey(for: e)] ?? e.color))
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
        store = Self.makeStore(events: latest, overrides: overrides)
    }

    /// 参加者の予定から、表示用の入れ物を組み立てる。バーはタイトルだけ(誰の予定かは日の一覧のアバターで見せる)。
    /// 色は、この端末で変えていればそれを使う
    static func makeStore(events: [SharedEvent], overrides: [String: String]) -> Store {
        let name = "shared-" + UUID().uuidString
        let store = Store(fileURL: FileManager.default.temporaryDirectory.appending(path: name + ".json"),
                          defaults: UserDefaults(suiteName: name) ?? .standard)
        let list = events.map { $0.shiftEvent(color: overrides[colorKey(for: $0)] ?? $0.color) }
        store.applySnapshot(SyncSnapshot(events: list, workplaces: [], favorites: [], customColors: [], hiddenSuggestions: []))
        return store
    }
}
