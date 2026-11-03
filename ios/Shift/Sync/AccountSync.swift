import CryptoKit
import Foundation
import Observation

/// 初回ログインで、端末とアカウントの両方にデータがあるときの確認用
struct SyncChoiceInfo: Equatable {
    let localCount: Int
    let remoteCount: Int
}

enum SyncChoice { case local, remote }

/// 画面に出す同期の状態
@Observable
final class SyncStatus {
    /// 新しい端末で、アカウントのデータを読み込み中
    var restoring = false
    /// 端末とアカウントのどちらを残すか、ユーザーの選択待ち
    var choice: SyncChoiceInfo?
    var lastSync: Date?
}

/// アカウント(Firestore)との同期。予定・職場などを 1 件ずつ送り、新しい変更が勝つ。
/// 端末には「最後に同期した内容」を控えておき、差分だけを送る(`ItemMeta`)。
@Observable
final class AccountSync {
    private struct ItemMeta: Codable, Equatable {
        var hash: String
        var updatedAt: Double
        var deleted: Bool
        var order: Int
    }

    private struct MetaFile: Codable {
        var initialized = false
        var items: [String: [String: ItemMeta]] = [:]
    }

    private struct LocalItem {
        let id: String
        let payload: String
        let order: Int
    }

    private struct SettingsPayload: Codable {
        var customColors: [String]
        var hiddenSuggestions: [String]
    }

    @MainActor private final class Gate { var done = false }

    static let settingsID = "main"

    let status: SyncStatus
    /// アカウントのデータを取り込んだあとに呼ぶ(ウィジェットやアラームの更新用)
    @ObservationIgnored var onApplied: (() -> Void)?

    @ObservationIgnored private weak var store: Store?
    @ObservationIgnored private let backing: RemoteDocs
    @ObservationIgnored private let metaDirectory: URL
    @ObservationIgnored private let fetchTimeout: Double
    @ObservationIgnored private let clock: () -> Double
    @ObservationIgnored private var uid: String?
    @ObservationIgnored private var meta = MetaFile()
    @ObservationIgnored private var pending: [SyncCollection: [RemoteDoc]]?
    @ObservationIgnored private var cancels: [() -> Void] = []
    @ObservationIgnored private var pushWork: DispatchWorkItem?
    @ObservationIgnored private var starting = false

    init(store: Store, backing: RemoteDocs, status: SyncStatus = SyncStatus(),
         metaDirectory: URL = URL.applicationSupportDirectory,
         fetchTimeout: Double = 10,
         clock: @escaping () -> Double = { Date().timeIntervalSince1970 }) {
        self.store = store
        self.backing = backing
        self.status = status
        self.metaDirectory = metaDirectory
        self.fetchTimeout = fetchTimeout
        self.clock = clock
    }

    private var metaURL: URL? {
        uid.map { metaDirectory.appending(path: "sync-meta-\($0).json") }
    }

    private var backupURL: URL { metaDirectory.appending(path: "sync-backup.json") }

    // MARK: 開始・停止

    @MainActor
    func start(uid: String) async {
        guard !starting else { return }
        stop()
        starting = true
        defer { starting = false }
        self.uid = uid
        loadMeta()
        if !meta.initialized {
            status.restoring = true
            let fetched = await fetchWithTimeout(uid: uid)
            status.restoring = false
            guard self.uid == uid else { return }
            // 取れなかったとき(オフラインなど)は、次の機会にやり直す。端末では今までどおり使える
            guard let fetched else { return }
            decideInitial(fetched)
            if status.choice != nil { return }
        }
        attach()
        pushDiff()
    }

    /// アプリを開き直したときなど、最初の取り込みが済んでいなければやり直す
    @MainActor
    func retryIfNeeded() {
        guard let uid, !meta.initialized, status.choice == nil, !starting else { return }
        Task { await start(uid: uid) }
    }

    func stop() {
        cancels.forEach { $0() }
        cancels = []
        pushWork?.cancel()
        pushWork = nil
        pending = nil
        status.choice = nil
        status.restoring = false
        uid = nil
        meta = MetaFile()
    }

    /// ユーザーの選択を受けて、初回の同期を進める
    @MainActor
    func resolve(_ choice: SyncChoice) {
        guard let fetched = pending, uid != nil else { return }
        pending = nil
        switch choice {
        case .remote:
            backupLocal()
            applyAll(fetched)
        case .local:
            seed(fetched)
        }
        meta.initialized = true
        saveMeta()
        status.choice = nil
        attach()
        pushDiff()
    }

    /// アカウントを削除する前に、クラウドのデータを消す。端末のデータは残る
    @MainActor
    func eraseRemote() async {
        guard let uid else { return }
        stop()
        try? await backing.deleteAll(uid: uid)
        try? FileManager.default.removeItem(at: metaDirectory.appending(path: "sync-meta-\(uid).json"))
    }

    // MARK: 最初の取り込み

    private func fetchWithTimeout(uid: String) async -> [SyncCollection: [RemoteDoc]]? {
        let backing = self.backing
        let seconds = fetchTimeout
        let gate = await Gate()
        return await withCheckedContinuation { (cont: CheckedContinuation<[SyncCollection: [RemoteDoc]]?, Never>) in
            Task { @MainActor in
                let r = try? await backing.fetchAll(uid: uid)
                if !gate.done { gate.done = true; cont.resume(returning: r) }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                if !gate.done { gate.done = true; cont.resume(returning: nil) }
            }
        }
    }

    private func liveCount(_ docs: [SyncCollection: [RemoteDoc]]) -> Int {
        var n = 0
        for (c, list) in docs where c != .settings {
            n += list.filter { !$0.deleted }.count
        }
        return n
    }

    private func decideInitial(_ fetched: [SyncCollection: [RemoteDoc]]) {
        guard let store else { return }
        let snap = store.syncSnapshot()
        let localCount = snap.events.count + snap.workplaces.count + snap.favorites.count + (snap.anniversaries?.count ?? 0)
        let remoteCount = liveCount(fetched)
        if localCount == 0, remoteCount == 0 {
            seed(fetched)
        } else if localCount == 0 {
            applyAll(fetched)
        } else if remoteCount == 0 {
            seed(fetched)
        } else {
            pending = fetched
            status.choice = SyncChoiceInfo(localCount: localCount, remoteCount: remoteCount)
            return
        }
        meta.initialized = true
        saveMeta()
    }

    /// 端末のデータを正とする。クラウドにだけあるものは、差分の送信で削除済みになる
    private func seed(_ fetched: [SyncCollection: [RemoteDoc]]) {
        meta.items = [:]
        for (c, docs) in fetched {
            for d in docs {
                meta.items[c.rawValue, default: [:]][d.id] =
                    ItemMeta(hash: "", updatedAt: d.updatedAt, deleted: d.deleted, order: d.order)
            }
        }
    }

    /// アカウントのデータで端末を置き換える
    private func applyAll(_ fetched: [SyncCollection: [RemoteDoc]]) {
        guard let store else { return }
        var snap = store.syncSnapshot()
        snap.events = []
        snap.workplaces = []
        snap.favorites = []
        snap.anniversaries = []
        meta.items = [:]
        for c in SyncCollection.allCases { _ = applyDocs(fetched[c] ?? [], c, into: &snap) }
        store.applySnapshot(snap)
        markSynced()
        onApplied?()
    }

    private func backupLocal() {
        guard let store, let data = try? JSONEncoder().encode(store.syncSnapshot()) else { return }
        try? data.write(to: backupURL, options: .atomic)
    }

    // MARK: 受信

    private func attach() {
        guard let uid else { return }
        cancels.forEach { $0() }
        cancels = SyncCollection.allCases.map { c in
            backing.listen(uid: uid, collection: c) { [weak self] docs in self?.received(docs, c) }
        }
    }

    private func received(_ docs: [RemoteDoc], _ c: SyncCollection) {
        guard meta.initialized, let store else { return }
        var snap = store.syncSnapshot()
        guard applyDocs(docs, c, into: &snap) else { return }
        store.applySnapshot(snap)
        saveMeta()
        markSynced()
        onApplied?()
    }

    /// 自分より新しいドキュメントだけを反映する。何か変わったら true
    private func applyDocs(_ docs: [RemoteDoc], _ c: SyncCollection, into snap: inout SyncSnapshot) -> Bool {
        var changed = false
        for d in docs.sorted(by: { $0.updatedAt < $1.updatedAt }) {
            if let m = meta.items[c.rawValue]?[d.id], d.updatedAt <= m.updatedAt { continue }
            switch c {
            case .events:
                if d.deleted { snap.events.removeAll { $0.id == d.id } }
                else if let v: ShiftEvent = decode(d.payload) { upsert(&snap.events, v) }
            case .workplaces:
                if d.deleted { snap.workplaces.removeAll { $0.id == d.id } }
                else if let v: Workplace = decode(d.payload) { upsert(&snap.workplaces, v) }
            case .favorites:
                if d.deleted { snap.favorites.removeAll { $0.id == d.id } }
                else if let v: ShiftEvent = decode(d.payload) { upsert(&snap.favorites, v) }
            case .anniversaries:
                var list = snap.anniversaries ?? []
                if d.deleted { list.removeAll { $0.id == d.id } }
                else if let v: Anniversary = decode(d.payload) { upsert(&list, v) }
                snap.anniversaries = list
            case .settings:
                if let v: SettingsPayload = decode(d.payload) {
                    snap.customColors = v.customColors
                    snap.hiddenSuggestions = v.hiddenSuggestions
                }
            }
            meta.items[c.rawValue, default: [:]][d.id] = ItemMeta(
                hash: d.deleted ? "" : Self.hash(d.payload, d.order),
                updatedAt: d.updatedAt, deleted: d.deleted, order: d.order)
            changed = true
        }
        if changed {
            if c == .workplaces { sortByOrder(&snap.workplaces, c) }
            if c == .favorites { sortByOrder(&snap.favorites, c) }
        }
        return changed
    }

    private func upsert<T: Identifiable>(_ list: inout [T], _ v: T) where T.ID == String {
        if let i = list.firstIndex(where: { $0.id == v.id }) { list[i] = v } else { list.append(v) }
    }

    private func sortByOrder<T: Identifiable>(_ list: inout [T], _ c: SyncCollection) where T.ID == String {
        let orders = meta.items[c.rawValue] ?? [:]
        list = list.enumerated()
            .sorted { (orders[$0.element.id]?.order ?? Int.max, $0.offset) < (orders[$1.element.id]?.order ?? Int.max, $1.offset) }
            .map(\.element)
    }

    // MARK: 送信

    /// 端末で変更があった。少し待ってからまとめて送る
    func localChanged() {
        guard meta.initialized, status.choice == nil, uid != nil else { return }
        pushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.pushDiff() }
        pushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    /// 控えと比べて、変わった 1 件ずつ・消えた 1 件ずつを送る
    func pushDiff() {
        guard let uid, meta.initialized, status.choice == nil, let store else { return }
        let snap = store.syncSnapshot()
        var sent = false
        for c in SyncCollection.allCases {
            let items = localItems(c, snap)
            var seen = Set<String>()
            for it in items {
                seen.insert(it.id)
                let h = Self.hash(it.payload, it.order)
                if let m = meta.items[c.rawValue]?[it.id], m.hash == h, !m.deleted { continue }
                let now = nextTime(after: meta.items[c.rawValue]?[it.id]?.updatedAt)
                backing.set(uid: uid, collection: c,
                            doc: RemoteDoc(id: it.id, payload: it.payload, updatedAt: now, deleted: false, order: it.order))
                meta.items[c.rawValue, default: [:]][it.id] = ItemMeta(hash: h, updatedAt: now, deleted: false, order: it.order)
                sent = true
            }
            for (id, m) in meta.items[c.rawValue] ?? [:] where !m.deleted && !seen.contains(id) && c != .settings {
                let now = nextTime(after: m.updatedAt)
                backing.set(uid: uid, collection: c,
                            doc: RemoteDoc(id: id, payload: "", updatedAt: now, deleted: true, order: m.order))
                meta.items[c.rawValue]?[id] = ItemMeta(hash: "", updatedAt: now, deleted: true, order: m.order)
                sent = true
            }
        }
        if sent {
            saveMeta()
            markSynced()
        }
    }

    private func nextTime(after previous: Double?) -> Double {
        max(clock(), (previous ?? 0) + 0.001)
    }

    private func localItems(_ c: SyncCollection, _ snap: SyncSnapshot) -> [LocalItem] {
        switch c {
        case .events: return snap.events.map { LocalItem(id: $0.id, payload: encode($0), order: 0) }
        case .workplaces: return snap.workplaces.enumerated().map { LocalItem(id: $1.id, payload: encode($1), order: $0) }
        case .favorites: return snap.favorites.enumerated().map { LocalItem(id: $1.id, payload: encode($1), order: $0) }
        case .anniversaries: return (snap.anniversaries ?? []).map { LocalItem(id: $0.id, payload: encode($0), order: 0) }
        case .settings:
            let s = SettingsPayload(customColors: snap.customColors, hiddenSuggestions: snap.hiddenSuggestions.sorted())
            return [LocalItem(id: Self.settingsID, payload: encode(s), order: 0)]
        }
    }

    // MARK: 部品

    private func markSynced() { status.lastSync = Date() }

    private func encode<T: Encodable>(_ v: T) -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return (try? e.encode(v)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private func decode<T: Decodable>(_ s: String) -> T? {
        try? JSONDecoder().decode(T.self, from: Data(s.utf8))
    }

    private static func hash(_ payload: String, _ order: Int) -> String {
        SHA256.hash(data: Data("\(payload)|\(order)".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func loadMeta() {
        meta = MetaFile()
        if let url = metaURL, let data = try? Data(contentsOf: url),
           let m = try? JSONDecoder().decode(MetaFile.self, from: data) {
            meta = m
        }
    }

    private func saveMeta() {
        guard let url = metaURL, let data = try? JSONEncoder().encode(meta) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
