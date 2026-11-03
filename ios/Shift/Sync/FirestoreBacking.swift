import FirebaseFirestore
import Foundation

/// Firestore の `users/{uid}/{collection}/{id}` に 1 件ずつ保存する
final class FirestoreBacking: RemoteDocs {
    private var db: Firestore { Firestore.firestore() }

    private func col(_ uid: String, _ c: SyncCollection) -> CollectionReference {
        db.collection("users").document(uid).collection(c.rawValue)
    }

    private static func doc(_ s: QueryDocumentSnapshot) -> RemoteDoc {
        let d = s.data()
        return RemoteDoc(id: s.documentID,
                         payload: d["payload"] as? String ?? "",
                         updatedAt: (d["updatedAt"] as? NSNumber)?.doubleValue ?? 0,
                         deleted: d["deleted"] as? Bool ?? false,
                         order: (d["order"] as? NSNumber)?.intValue ?? 0)
    }

    func fetchAll(uid: String) async throws -> [SyncCollection: [RemoteDoc]] {
        var out: [SyncCollection: [RemoteDoc]] = [:]
        for c in SyncCollection.allCases {
            let snap = try await col(uid, c).getDocuments()
            out[c] = snap.documents.map(Self.doc)
        }
        return out
    }

    func set(uid: String, collection: SyncCollection, doc: RemoteDoc) {
        col(uid, collection).document(doc.id).setData([
            "payload": doc.payload,
            "updatedAt": doc.updatedAt,
            "deleted": doc.deleted,
            "order": doc.order,
        ])
    }

    func listen(uid: String, collection: SyncCollection, onDocs: @escaping ([RemoteDoc]) -> Void) -> () -> Void {
        let registration = col(uid, collection).addSnapshotListener { snap, _ in
            guard let snap else { return }
            let docs = snap.documentChanges.filter { $0.type != .removed }.map { Self.doc($0.document) }
            if !docs.isEmpty { onDocs(docs) }
        }
        return { registration.remove() }
    }

    func deleteAll(uid: String) async throws {
        for c in SyncCollection.allCases {
            let snap = try await col(uid, c).getDocuments()
            for d in snap.documents { try await d.reference.delete() }
        }
    }
}
