import FirebaseFirestore
import Foundation

/// Firestore の `calendars/{id}`(名前・持ち主・members・invites)と、自分の参加一覧 `users/{uid}/calendars/{id}`
final class FirestoreCalendarBacking: CalendarBacking {
    private static let inviteDays: Double = 30

    private var db: Firestore { Firestore.firestore() }
    private func calendar(_ id: String) -> DocumentReference { db.collection("calendars").document(id) }
    private func member(_ cid: String, _ uid: String) -> DocumentReference {
        calendar(cid).collection("members").document(uid)
    }
    private func index(_ uid: String) -> CollectionReference { db.collection("users").document(uid).collection("calendars") }

    private static func nowMillis() -> Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    private static func isDenied(_ error: Error) -> Bool {
        let e = error as NSError
        return e.domain == FirestoreErrorDomain && e.code == FirestoreErrorCode.permissionDenied.rawValue
    }

    private static func calendar(id: String, data: [String: Any], status: MemberStatus) -> SharedCalendar {
        SharedCalendar(id: id,
                       name: data["name"] as? String ?? "",
                       ownerUid: data["ownerUid"] as? String ?? "",
                       kind: CalendarKind(rawValue: data["kind"] as? String ?? "") ?? .mutual,
                       requireApproval: data["requireApproval"] as? Bool ?? false,
                       status: status)
    }

    func create(uid: String, spec: NewCalendar) async throws -> (calendar: SharedCalendar, invite: InviteCode) {
        let cal = SharedCalendar(id: InviteCode.random(length: 12), name: spec.name, ownerUid: uid,
                                 kind: spec.kind, requireApproval: spec.requireApproval, status: .active)
        let token = InviteCode.random(length: 16)
        let now = Self.nowMillis()
        let batch = db.batch()
        batch.setData(["name": spec.name, "ownerUid": uid, "kind": spec.kind.rawValue,
                       "requireApproval": spec.requireApproval, "createdAt": now],
                      forDocument: calendar(cal.id))
        batch.setData(["role": "owner", "status": "active", "displayName": spec.displayName,
                       "sharedKeys": spec.sharedKeys, "joinedAt": now],
                      forDocument: member(cal.id, uid))
        batch.setData(["createdBy": uid, "revoked": false, "expiresAt": now + Self.inviteDays * 86_400_000,
                       "calendarName": spec.name, "ownerName": spec.displayName,
                       "kind": spec.kind.rawValue, "requireApproval": spec.requireApproval],
                      forDocument: calendar(cal.id).collection("invites").document(token))
        batch.setData(Self.indexData(cal), forDocument: index(uid).document(cal.id))
        try await batch.commit()
        return (cal, InviteCode(calendarId: cal.id, token: token))
    }

    private static func indexData(_ cal: SharedCalendar) -> [String: Any] {
        ["name": cal.name, "ownerUid": cal.ownerUid, "kind": cal.kind.rawValue, "requireApproval": cal.requireApproval]
    }

    func joined(uid: String) async throws -> [SharedCalendar] {
        let snap = try await index(uid).getDocuments()
        var out: [SharedCalendar] = []
        for d in snap.documents {
            // 自分の参加の状態は、members の自分の分を見る。消されていたら一覧から外す
            let m = try? await member(d.documentID, uid).getDocument()
            guard let data = m?.data() else { continue }
            let status = MemberStatus(rawValue: data["status"] as? String ?? "") ?? .active
            out.append(Self.calendar(id: d.documentID, data: d.data(), status: status))
        }
        return out
    }

    private func invite(_ code: InviteCode) async throws -> [String: Any] {
        let snap: DocumentSnapshot
        do {
            snap = try await calendar(code.calendarId).collection("invites").document(code.token).getDocument()
        } catch {
            if Self.isDenied(error) { throw CalendarError.invalidInvite }
            throw error
        }
        guard let data = snap.data(), data["revoked"] as? Bool == false,
              (data["expiresAt"] as? NSNumber)?.doubleValue ?? 0 > Self.nowMillis() else { throw CalendarError.invalidInvite }
        return data
    }

    func preview(code: InviteCode) async throws -> InvitePreview {
        let data = try await invite(code)
        return InvitePreview(calendarName: data["calendarName"] as? String ?? "",
                             ownerName: data["ownerName"] as? String ?? "",
                             kind: CalendarKind(rawValue: data["kind"] as? String ?? "") ?? .mutual,
                             requireApproval: data["requireApproval"] as? Bool ?? false)
    }

    func join(uid: String, code: InviteCode, displayName: String, sharedKeys: [String]) async throws -> SharedCalendar {
        let data = try await invite(code)
        let requireApproval = data["requireApproval"] as? Bool ?? false
        let kind = CalendarKind(rawValue: data["kind"] as? String ?? "") ?? .mutual
        let status: MemberStatus = requireApproval ? .pending : .active
        do {
            try await member(code.calendarId, uid).setData([
                "role": "member", "status": status.rawValue, "displayName": displayName,
                // 見せるだけのカレンダーでは、参加者は何も共有しない
                "sharedKeys": kind == .oneway ? [] : sharedKeys,
                "joinedAt": Self.nowMillis(), "token": code.token,
            ])
        } catch {
            if Self.isDenied(error) { throw CalendarError.invalidInvite }
            throw error
        }
        let cal = SharedCalendar(id: code.calendarId, name: data["calendarName"] as? String ?? "",
                                 ownerUid: data["createdBy"] as? String ?? "", kind: kind,
                                 requireApproval: requireApproval, status: status)
        try await index(uid).document(cal.id).setData(Self.indexData(cal))
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
        try await invites.document(token).setData([
            "createdBy": uid, "revoked": false, "expiresAt": now + Self.inviteDays * 86_400_000,
            "calendarName": cal.name, "ownerName": "", "kind": cal.kind.rawValue, "requireApproval": cal.requireApproval,
        ])
        return InviteCode(calendarId: cal.id, token: token)
    }

    func leave(uid: String, calendarId: String) async throws {
        try await member(calendarId, uid).delete()
        try await index(uid).document(calendarId).delete()
    }

    func members(calendarId: String) async throws -> [CalendarMember] {
        let snap = try await calendar(calendarId).collection("members").getDocuments()
        return snap.documents.map { d in
            let x = d.data()
            return CalendarMember(id: d.documentID,
                                  displayName: x["displayName"] as? String ?? "",
                                  isOwner: x["role"] as? String == "owner",
                                  status: MemberStatus(rawValue: x["status"] as? String ?? "") ?? .active,
                                  sharedKeys: x["sharedKeys"] as? [String] ?? [])
        }
        .sorted { ($0.isOwner ? 0 : 1, $0.displayName) < ($1.isOwner ? 0 : 1, $1.displayName) }
    }

    func setStatus(calendarId: String, uid: String, status: MemberStatus) async throws {
        try await member(calendarId, uid).updateData(["status": status.rawValue])
    }

    func removeMember(calendarId: String, uid: String) async throws {
        try await member(calendarId, uid).delete()
    }

    func updateMine(calendarId: String, uid: String, displayName: String, sharedKeys: [String]) async throws {
        try await member(calendarId, uid).updateData(["displayName": displayName, "sharedKeys": sharedKeys])
    }
}
