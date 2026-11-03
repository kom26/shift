import Foundation
import Testing
@testable import Shift

private final class MemoryBacking: KeyValueBacking {
    var datas: [String: Data] = [:]
    var doubles: [String: Double] = [:]
    func data(forKey key: String) -> Data? { datas[key] }
    func double(forKey key: String) -> Double { doubles[key] ?? 0 }
    func set(_ data: Data, forKey key: String) { datas[key] = data }
    func set(_ value: Double, forKey key: String) { doubles[key] = value }
    func synchronize() -> Bool { true }
}

struct CloudSyncTests {
    private func makeStore() -> Store {
        let name = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appending(path: name + ".json")
        return Store(fileURL: url, defaults: UserDefaults(suiteName: name)!)
    }

    private func makeSync(_ store: Store, _ backing: MemoryBacking) -> CloudSync {
        let name = UUID().uuidString
        let backup = FileManager.default.temporaryDirectory.appending(path: name + "-backup.json")
        return CloudSync(store: store, backing: backing, defaults: UserDefaults(suiteName: name)!, backupURL: backup)
    }

    @Test func existingDataIsPushedWhenICloudIsEmpty() throws {
        let store = makeStore()
        store.save(ev("a", "2026-10-20"))
        let backing = MemoryBacking()
        makeSync(store, backing).reconcile()
        let data = try #require(backing.datas["snapshot"])
        let snap = try JSONDecoder().decode(SyncSnapshot.self, from: data)
        #expect(snap.events.map(\.id) == ["a"])
        #expect((backing.doubles["snapshot.t"] ?? 0) > 0)
    }

    @Test func newDeviceAdoptsICloudData() {
        let first = makeStore()
        first.save(ev("a", "2026-10-20"))
        first.addWorkplace(name: "A店", color: "#111111")
        let backing = MemoryBacking()
        makeSync(first, backing).reconcile()

        let second = makeStore()
        makeSync(second, backing).reconcile()
        #expect(second.events.map(\.id) == ["a"])
        #expect(second.workplaces.map(\.name) == ["A店"])
    }

    @Test func remoteChangesDoNotEchoBack() {
        let first = makeStore()
        first.save(ev("a", "2026-10-20"))
        let backing = MemoryBacking()
        makeSync(first, backing).reconcile()
        let second = makeStore()
        var echoed = false
        second.onLocalChange = { echoed = true }
        makeSync(second, backing).reconcile()
        #expect(!echoed)
    }

    private func makeSync(_ store: Store, _ backing: MemoryBacking, available: Bool, timeout: TimeInterval = 8) -> CloudSync {
        let name = UUID().uuidString
        let backup = FileManager.default.temporaryDirectory.appending(path: name + "-backup.json")
        return CloudSync(store: store, backing: backing, defaults: UserDefaults(suiteName: name)!, backupURL: backup,
                         available: { available }, restoreTimeout: timeout)
    }

    @Test func emptyNewDeviceWaitsForICloudData() {
        let store = makeStore()
        let sync = makeSync(store, MemoryBacking(), available: true)
        defer { withExtendedLifetime(store) {} }
        sync.start()
        #expect(sync.status.restoring)
        sync.localChanged()
        #expect(sync.status.restoring)
    }

    @Test func restoringEndsWhenICloudDataArrives() {
        let first = makeStore()
        first.save(ev("a", "2026-10-20"))
        let backing = MemoryBacking()
        makeSync(first, backing).reconcile()

        let second = makeStore()
        let sync = makeSync(second, backing, available: true)
        // データが届く前に始まった状態を作る
        let empty = MemoryBacking()
        let late = makeSync(second, empty, available: true)
        late.start()
        #expect(late.status.restoring)
        empty.datas = backing.datas
        empty.doubles = backing.doubles
        late.reconcile()
        #expect(!late.status.restoring)
        #expect(second.events.map(\.id) == ["a"])
        _ = sync
    }

    @Test func notWaitingWhenSignedOutOrAlreadyHasData() {
        let s0 = makeStore()
        defer { withExtendedLifetime(s0) {} }
        let signedOut = makeSync(s0, MemoryBacking(), available: false)
        signedOut.start()
        #expect(!signedOut.status.restoring)

        let store = makeStore()
        store.save(ev("a", "2026-10-20"))
        let withData = makeSync(store, MemoryBacking(), available: true)
        withData.start()
        #expect(!withData.status.restoring)
    }

    @Test func restoringEndsByTimeout() async throws {
        let store = makeStore()
        defer { withExtendedLifetime(store) {} }
        let sync = makeSync(store, MemoryBacking(), available: true, timeout: 0.1)
        sync.start()
        #expect(sync.status.restoring)
        try await Task.sleep(for: .seconds(0.4))
        #expect(!sync.status.restoring)
    }

    @Test func tooLargeSnapshotIsNotPushed() {
        let store = makeStore()
        var big = ev("a", "2026-10-20")
        big.memo = String(repeating: "x", count: CloudSync.maxBytes + 10)
        store.save(big)
        let backing = MemoryBacking()
        let sync = makeSync(store, backing)
        sync.reconcile()
        #expect(sync.tooLarge)
        #expect(backing.datas["snapshot"] == nil)
    }
}
