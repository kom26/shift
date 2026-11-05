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

    /// 共有カレンダーの画面で、同じカレンダー部品に表示するための予定(見るだけ)
    func shiftEvent(prefix: String) -> ShiftEvent {
        ShiftEvent(id: id, title: prefix + title, memo: "", color: color, startDate: startDate, endDate: endDate,
                   placed: true, allDay: allDay, startTime: startTime, endTime: endTime, workHours: nil,
                   barShowsTitle: true)
    }
}

/// 共有カレンダーの予定のクラウド側(テストでは差し替える)
protocol SharedEventsBacking: AnyObject {
    func fetch(calendarId: String) async throws -> [SharedEvent]
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
                for id in remote where desired[id] == nil { try await backing.delete(calendarId: cal.id, id: id) }
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

/// 共有カレンダーを開いている間の表示。参加者の予定を 1 つのカレンダーに重ねる(見るだけ)
@MainActor
@Observable
final class SharedViewState {
    private(set) var calendar: SharedCalendar?
    /// 表示用の入れ物。自分のデータとは別なので、ここでどう動かしても自分の予定は変わらない
    private(set) var store: Store?
    private(set) var loading = false
    private(set) var failed = false

    @ObservationIgnored private let events: SharedEventsBacking
    @ObservationIgnored private let calendars: CalendarService

    init(events: SharedEventsBacking, calendars: CalendarService) {
        self.events = events
        self.calendars = calendars
    }

    var isOpen: Bool { calendar != nil }

    func open(_ cal: SharedCalendar) async {
        calendar = cal
        store = Self.makeStore(events: [], names: [:], showNames: false)
        await refresh()
    }

    func close() {
        calendar = nil
        store = nil
        failed = false
    }

    func refresh() async {
        guard let cal = calendar else { return }
        loading = true
        failed = false
        defer { loading = false }
        do {
            let list = try await events.fetch(calendarId: cal.id)
            let members = await calendars.members(of: cal) ?? []
            let names = Dictionary(members.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
            guard calendar?.id == cal.id else { return }
            store = Self.makeStore(events: list, names: names, showNames: cal.kind == .mutual)
        } catch {
            failed = true
        }
    }

    /// 参加者の予定から、表示用の入れ物を組み立てる(名前つきの予定名にする。見せるだけでは持ち主だけなので名前は付けない)
    static func makeStore(events: [SharedEvent], names: [String: String], showNames: Bool) -> Store {
        let name = "shared-" + UUID().uuidString
        let store = Store(fileURL: FileManager.default.temporaryDirectory.appending(path: name + ".json"),
                          defaults: UserDefaults(suiteName: name) ?? .standard)
        let list = events.map { e -> ShiftEvent in
            let who = names[e.ownerUid] ?? ""
            return e.shiftEvent(prefix: showNames && !who.isEmpty ? who + "｜" : "")
        }
        store.applySnapshot(SyncSnapshot(events: list, workplaces: [], favorites: [], customColors: [], hiddenSuggestions: []))
        return store
    }
}
