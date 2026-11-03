import Foundation
import Testing
@testable import Shift

private final class FakeRemote: RemoteDocs {
    var docs: [SyncCollection: [String: RemoteDoc]] = [:]
    var listeners: [SyncCollection: ([RemoteDoc]) -> Void] = [:]
    var writes = 0

    func fetchAll(uid: String) async throws -> [SyncCollection: [RemoteDoc]] {
        var out: [SyncCollection: [RemoteDoc]] = [:]
        for (c, d) in docs { out[c] = Array(d.values) }
        return out
    }

    func set(uid: String, collection: SyncCollection, doc: RemoteDoc) {
        writes += 1
        docs[collection, default: [:]][doc.id] = doc
    }

    func listen(uid: String, collection: SyncCollection, onDocs: @escaping ([RemoteDoc]) -> Void) -> () -> Void {
        listeners[collection] = onDocs
        return { [weak self] in self?.listeners[collection] = nil }
    }

    func deleteAll(uid: String) async throws { docs = [:] }

    /// 別の端末から届いた変更
    func push(_ c: SyncCollection, _ doc: RemoteDoc) {
        docs[c, default: [:]][doc.id] = doc
        listeners[c]?([doc])
    }
}

@MainActor
private final class Rig {
    let store: Store
    let remote: FakeRemote
    let sync: AccountSync
    var time = 1000.0

    init(remote: FakeRemote = FakeRemote()) {
        let name = UUID().uuidString
        store = Store(fileURL: FileManager.default.temporaryDirectory.appending(path: name + ".json"),
                      defaults: UserDefaults(suiteName: name)!)
        self.remote = remote
        let dir = FileManager.default.temporaryDirectory.appending(path: "sync-" + name)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var t = 1000.0
        sync = AccountSync(store: store, backing: remote, metaDirectory: dir, fetchTimeout: 2,
                           clock: { t += 1; return t })
    }
}

@MainActor
struct AccountSyncTests {
    private func doc(_ e: ShiftEvent, at t: Double, deleted: Bool = false) -> RemoteDoc {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let s = String(data: (try? enc.encode(e)) ?? Data(), encoding: .utf8) ?? ""
        return RemoteDoc(id: e.id, payload: deleted ? "" : s, updatedAt: t, deleted: deleted, order: 0)
    }

    @Test func localOnlyDataIsSentOnFirstLogin() async {
        let rig = Rig()
        rig.store.save(ev("a", "2026-10-20"))
        await rig.sync.start(uid: "u1")
        #expect(rig.remote.docs[.events]?["a"] != nil)
        #expect(rig.sync.status.choice == nil)
    }

    @Test func remoteOnlyDataIsAdoptedOnFirstLogin() async {
        let remote = FakeRemote()
        remote.docs[.events] = ["r": doc(ev("r", "2026-10-21"), at: 500)]
        let rig = Rig(remote: remote)
        await rig.sync.start(uid: "u1")
        #expect(rig.store.events.map(\.id) == ["r"])
        #expect(rig.sync.status.choice == nil)
    }

    @Test func bothSidesAsksAndRemoteChoiceReplacesLocal() async {
        let remote = FakeRemote()
        remote.docs[.events] = ["r": doc(ev("r", "2026-10-21"), at: 500)]
        let rig = Rig(remote: remote)
        rig.store.save(ev("a", "2026-10-20"))
        await rig.sync.start(uid: "u1")
        #expect(rig.sync.status.choice == SyncChoiceInfo(localCount: 1, remoteCount: 1))
        #expect(rig.store.events.map(\.id) == ["a"])
        rig.sync.resolve(.remote)
        #expect(rig.store.events.map(\.id) == ["r"])
        #expect(rig.sync.status.choice == nil)
    }

    @Test func bothSidesLocalChoiceDeletesRemoteOnly() async {
        let remote = FakeRemote()
        remote.docs[.events] = ["r": doc(ev("r", "2026-10-21"), at: 500)]
        let rig = Rig(remote: remote)
        rig.store.save(ev("a", "2026-10-20"))
        await rig.sync.start(uid: "u1")
        rig.sync.resolve(.local)
        #expect(rig.store.events.map(\.id) == ["a"])
        #expect(rig.remote.docs[.events]?["a"]?.deleted == false)
        #expect(rig.remote.docs[.events]?["r"]?.deleted == true)
    }

    @Test func nothingIsSentUntilChoiceIsMade() async {
        let remote = FakeRemote()
        remote.docs[.events] = ["r": doc(ev("r", "2026-10-21"), at: 500)]
        let rig = Rig(remote: remote)
        rig.store.save(ev("a", "2026-10-20"))
        await rig.sync.start(uid: "u1")
        rig.sync.pushDiff()
        #expect(rig.remote.writes == 0)
    }

    @Test func editsAndDeletesAreSentOneByOne() async {
        let rig = Rig()
        rig.store.save(ev("a", "2026-10-20"))
        rig.store.save(ev("b", "2026-10-21"))
        await rig.sync.start(uid: "u1")
        let before = rig.remote.writes

        var a = rig.store.events[0]
        a.title = "変更"
        rig.store.save(a)
        rig.sync.pushDiff()
        #expect(rig.remote.writes == before + 1)

        rig.store.delete(id: "b")
        rig.sync.pushDiff()
        #expect(rig.remote.docs[.events]?["b"]?.deleted == true)

        // 変更がなければ何も送らない
        let n = rig.remote.writes
        rig.sync.pushDiff()
        #expect(rig.remote.writes == n)
    }

    @Test func newerRemoteChangeWinsAndOlderIsIgnored() async {
        let rig = Rig()
        rig.store.save(ev("a", "2026-10-20"))
        await rig.sync.start(uid: "u1")
        let sent = rig.remote.docs[.events]?["a"]?.updatedAt ?? 0

        var newer = rig.store.events[0]
        newer.title = "他の端末"
        rig.remote.push(.events, doc(newer, at: sent + 100))
        #expect(rig.store.events.first?.title == "他の端末")

        var older = newer
        older.title = "古い"
        rig.remote.push(.events, doc(older, at: sent + 50))
        #expect(rig.store.events.first?.title == "他の端末")
    }

    @Test func remoteDeleteRemovesLocalAndDoesNotEchoBack() async {
        let rig = Rig()
        rig.store.save(ev("a", "2026-10-20"))
        await rig.sync.start(uid: "u1")
        let sent = rig.remote.docs[.events]?["a"]?.updatedAt ?? 0
        var echoed = false
        rig.store.onLocalChange = { echoed = true }
        rig.remote.push(.events, doc(rig.store.events[0], at: sent + 10, deleted: true))
        #expect(rig.store.events.isEmpty)
        #expect(!echoed)
        let writes = rig.remote.writes
        rig.sync.pushDiff()
        #expect(rig.remote.writes == writes)
    }

    @Test func workplaceOrderIsKept() async {
        let rig = Rig()
        rig.store.addWorkplace(name: "A", color: "#111111")
        rig.store.addWorkplace(name: "B", color: "#222222")
        await rig.sync.start(uid: "u1")
        let other = Rig(remote: rig.remote)
        await other.sync.start(uid: "u1")
        #expect(other.store.workplaces.map(\.name) == ["A", "B"])
    }

    @Test func eraseRemoteClearsAccountDataButKeepsLocal() async {
        let rig = Rig()
        rig.store.save(ev("a", "2026-10-20"))
        await rig.sync.start(uid: "u1")
        await rig.sync.eraseRemote()
        #expect(rig.remote.docs.isEmpty)
        #expect(rig.store.events.map(\.id) == ["a"])
    }
}
