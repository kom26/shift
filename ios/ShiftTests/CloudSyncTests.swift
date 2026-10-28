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
