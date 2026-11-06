import FirebaseFirestore
import Foundation

/// Firestore の `calendars/{id}/events/{eventId}`。公開できる項目だけを置く
final class FirestoreSharedEvents: SharedEventsBacking {
    private var db: Firestore { Firestore.firestore() }
    private func col(_ id: String) -> CollectionReference {
        db.collection("calendars").document(id).collection("events")
    }

    private static func event(_ d: QueryDocumentSnapshot) -> SharedEvent? {
        let x = d.data()
        guard let ownerUid = x["ownerUid"] as? String, let start = x["startDate"] as? String else { return nil }
        return SharedEvent(id: d.documentID, ownerUid: ownerUid, sourceKey: x["sourceKey"] as? String ?? "",
                           title: x["title"] as? String ?? "", startDate: start,
                           endDate: x["endDate"] as? String ?? start,
                           startTime: x["startTime"] as? String, endTime: x["endTime"] as? String,
                           allDay: x["allDay"] as? Bool ?? true,
                           name: x["name"] as? String ?? "", color: x["color"] as? String ?? "#bec1cc",
                           barTime: x["barTime"] as? Bool ?? false, placed: x["placed"] as? Bool ?? true)
    }

    func fetch(calendarId: String) async throws -> [SharedEvent] {
        try await col(calendarId).getDocuments().documents.compactMap(Self.event)
    }

    func listen(calendarId: String, onChange: @escaping ([SharedEvent]) -> Void) -> () -> Void {
        let registration = col(calendarId).addSnapshotListener { snap, _ in
            guard let snap else { return }
            onChange(snap.documents.compactMap(Self.event))
        }
        return { registration.remove() }
    }

    func set(calendarId: String, event e: SharedEvent) async throws {
        var data: [String: Any] = [
            "ownerUid": e.ownerUid, "sourceKey": e.sourceKey, "title": e.title,
            "startDate": e.startDate, "endDate": e.endDate, "allDay": e.allDay,
            "name": e.name, "color": e.color, "barTime": e.barTime, "placed": e.placed,
        ]
        if let t = e.startTime { data["startTime"] = t }
        if let t = e.endTime { data["endTime"] = t }
        try await col(calendarId).document(e.id).setData(data)
    }

    func delete(calendarId: String, id: String) async throws {
        try await col(calendarId).document(id).delete()
    }

    func mineIds(calendarId: String, uid: String) async throws -> Set<String> {
        let snap = try await col(calendarId).whereField("ownerUid", isEqualTo: uid).getDocuments()
        return Set(snap.documents.map(\.documentID))
    }
}
