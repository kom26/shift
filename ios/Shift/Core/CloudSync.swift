import Foundation

/// 端末間で同期するデータ一式
struct SyncSnapshot: Codable, Equatable {
    var events: [ShiftEvent]
    var workplaces: [Workplace]
    var favorites: [ShiftEvent]
    var customColors: [String]
    var hiddenSuggestions: [String]
    /// セット済みのアラームの記録。新しい端末では AlarmKit 側に実体がないので、許可を取り直して入れ直す
    var alarms: [AlarmEntry]?

    var isEmpty: Bool { events.isEmpty && workplaces.isEmpty && favorites.isEmpty }
}

/// iCloud のキーバリューストアに相当する入れ物(テストでは差し替える)
protocol KeyValueBacking: AnyObject {
    func data(forKey key: String) -> Data?
    func double(forKey key: String) -> Double
    func set(_ data: Data, forKey key: String)
    func set(_ value: Double, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

final class UbiquitousBacking: KeyValueBacking {
    private let kv = NSUbiquitousKeyValueStore.default
    func data(forKey key: String) -> Data? { kv.data(forKey: key) }
    func double(forKey key: String) -> Double { kv.double(forKey: key) }
    func set(_ data: Data, forKey key: String) { kv.set(data, forKey: key) }
    func set(_ value: Double, forKey key: String) { kv.set(value, forKey: key) }
    @discardableResult func synchronize() -> Bool { kv.synchronize() }
}

/// iCloud でデータを自動同期する。サインイン操作は不要で、iPhone が iCloud にサインインしていれば動く。
/// 競合は「あとから変更したほうが勝つ」(全体を1つのスナップショットとして扱う)。
final class CloudSync {
    /// iCloud のキーバリューストアは全体で 1MB まで。余裕を見て超えたら同期を止める
    static let maxBytes = 900_000
    private static let snapshotKey = "snapshot"
    private static let timeKey = "snapshot.t"
    private static let localTimeKey = "sync.localTime"
    private static let lastSyncKey = "sync.lastSync"

    private let backing: KeyValueBacking
    private let defaults: UserDefaults
    private let backupURL: URL
    private weak var store: Store?
    private var pushWork: DispatchWorkItem?
    private var observer: NSObjectProtocol?

    private(set) var tooLarge = false
    /// iCloud のデータを取り込んだあとに呼ぶ(アラームの入れ直し用)
    var onApplied: (() -> Void)?

    init(store: Store, backing: KeyValueBacking = UbiquitousBacking(),
         defaults: UserDefaults = .standard,
         backupURL: URL = URL.applicationSupportDirectory.appending(path: "sync-backup.json")) {
        self.store = store
        self.backing = backing
        self.defaults = defaults
        self.backupURL = backupURL
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// iPhone が iCloud にサインインしているか
    static var iCloudAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }

    /// 最後に iCloud と同期した日時(設定画面の表示用)
    static var lastSync: Date? {
        let t = UserDefaults.standard.double(forKey: lastSyncKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    func start() {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil, queue: .main) { [weak self] _ in self?.reconcile() }
        backing.synchronize()
        reconcile()
    }

    /// アプリを開いたとき・iCloud 側が変わったときに、新しいほうに揃える
    func reconcile() {
        guard let store else { return }
        let remoteT = backing.double(forKey: Self.timeKey)
        let localT = defaults.double(forKey: Self.localTimeKey)
        let remote = backing.data(forKey: Self.snapshotKey).flatMap { try? JSONDecoder().decode(SyncSnapshot.self, from: $0) }
        if let remote, remoteT > localT {
            // 一度も同期していない端末にデータがあるときは、念のため退避してから取り込む
            let current = store.syncSnapshot()
            if localT == 0, !current.isEmpty, let data = try? JSONEncoder().encode(current) {
                try? data.write(to: backupURL, options: .atomic)
            }
            store.applySnapshot(remote)
            defaults.set(remoteT, forKey: Self.localTimeKey)
            markSynced()
            onApplied?()
        } else if localT > remoteT || (remote == nil && !store.syncSnapshot().isEmpty) {
            if localT == 0 { defaults.set(Date().timeIntervalSince1970, forKey: Self.localTimeKey) }
            push()
        }
    }

    /// 端末で変更があった。少し待ってからまとめて送る
    func localChanged() {
        defaults.set(Date().timeIntervalSince1970, forKey: Self.localTimeKey)
        pushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.push() }
        pushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    func push() {
        guard let store, let data = try? JSONEncoder().encode(store.syncSnapshot()) else { return }
        guard data.count <= Self.maxBytes else {
            tooLarge = true
            return
        }
        tooLarge = false
        backing.set(data, forKey: Self.snapshotKey)
        backing.set(defaults.double(forKey: Self.localTimeKey), forKey: Self.timeKey)
        backing.synchronize()
        markSynced()
    }

    private func markSynced() {
        defaults.set(Date().timeIntervalSince1970, forKey: Self.lastSyncKey)
    }
}
