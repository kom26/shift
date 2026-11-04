import FirebaseFirestore
import Foundation

/// Firestore の `calendars/{id}`(名前・持ち主・members・invites)と、自分の参加一覧 `users/{uid}/calendars/{id}`
final class FirestoreCalendarBacking: CalendarBacking {
    private static let inviteDays: Double = 30

    private var db: Firestore { Firestore.firestore() }
    private func calendar(_ id: String) -> DocumentReference { db.collection("calendars").document(id) }
    private func index(_ uid: String) -> CollectionReference { db.collection("users").document(uid).collection("calendars") }

    private static func nowMillis() -> Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    func create(uid: String, name: String) async throws -> (calendar: SharedCalendar, invite: InviteCode) {
        let cal = SharedCalendar(id: InviteCode.random(length: 12), name: name, ownerUid: uid)
        let token = InviteCode.random(length: 16)
        let now = Self.nowMillis()
        let batch = db.batch()
        batch.setData(["name": name, "ownerUid": uid, "createdAt": now], forDocument: calendar(cal.id))
        batch.setData(["role": "owner", "joinedAt": now], forDocument: calendar(cal.id).collection("members").document(uid))
        batch.setData(["createdBy": uid, "revoked": false, "expiresAt": now + Self.inviteDays * 86_400_000],
                      forDocument: calendar(cal.id).collection("invites").document(token))
        batch.setData(["name": name, "ownerUid": uid], forDocument: index(uid).document(cal.id))
        try await batch.commit()
        return (cal, InviteCode(calendarId: cal.id, token: token))
    }

    func joined(uid: String) async throws -> [SharedCalendar] {
        let snap = try await index(uid).getDocuments()
        return snap.documents.map {
            SharedCalendar(id: $0.documentID,
                           name: $0.data()["name"] as? String ?? "",
                           ownerUid: $0.data()["ownerUid"] as? String ?? "")
        }
    }

    func join(uid: String, code: InviteCode) async throws -> SharedCalendar {
        let member = calendar(code.calendarId).collection("members").document(uid)
        do {
            try await member.setData(["role": "member", "joinedAt": Self.nowMillis(), "token": code.token])
        } catch let error as NSError where error.domain == FirestoreErrorDomain && error.code == FirestoreErrorCode.permissionDenied.rawValue {
            throw CalendarError.invalidInvite
        }
        let snap = try await calendar(code.calendarId).getDocument()
        guard let data = snap.data() else { throw CalendarError.invalidInvite }
        let cal = SharedCalendar(id: code.calendarId,
                                 name: data["name"] as? String ?? "",
                                 ownerUid: data["ownerUid"] as? String ?? "")
        try await index(uid).document(cal.id).setData(["name": cal.name, "ownerUid": cal.ownerUid])
        return cal
    }

    func currentInvite(uid: String, calendar cal: SharedCalendar) async throws -> InviteCode {
        let invites = calendar(cal.id).collection("invites")
        let now = Self.nowMillis()
        let snap = try await invites.whereField("revoked", isEqualTo: false).getDocuments()
        if let valid = snap.documents.first(where: { ($0.data()["expiresAt"] as? NSNumber)?.doubleValue ?? 0 > now }) {
            return InviteCode(calendarId: cal.id, token: valid.documentID)
        }
        let token = InviteCode.random(length: 16)
        try await invites.document(token).setData(["createdBy": uid, "revoked": false,
                                                   "expiresAt": now + Self.inviteDays * 86_400_000])
        return InviteCode(calendarId: cal.id, token: token)
    }

    func leave(uid: String, calendarId: String) async throws {
        try await calendar(calendarId).collection("members").document(uid).delete()
        try await index(uid).document(calendarId).delete()
    }
}
