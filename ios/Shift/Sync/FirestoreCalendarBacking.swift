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

    private static func calendar(id: String, data: [String: Any], status: MemberStatus, sharedKeys: [String] = [],
                                 shareManual: Bool = false) -> SharedCalendar {
        SharedCalendar(id: id,
                       name: data["name"] as? String ?? "",
                       ownerUid: data["ownerUid"] as? String ?? "",
                       kind: CalendarKind(rawValue: data["kind"] as? String ?? "") ?? .mutual,
                       requireApproval: data["requireApproval"] as? Bool ?? false,
                       status: status, mySharedKeys: sharedKeys,
                       icon: CalendarIcon.resolved(data["icon"] as? String ?? ""), myShareManual: shareManual)
    }

    func create(uid: String, spec: NewCalendar) async throws -> (calendar: SharedCalendar, invite: InviteCode) {
        var cal = SharedCalendar(id: InviteCode.random(length: 12), name: spec.name, ownerUid: uid,
                                 kind: spec.kind, requireApproval: spec.requireApproval, status: .active,
                                 icon: CalendarIcon.resolved(spec.icon))
        let token = InviteCode.random(length: 16)
        let now = Self.nowMillis()
        cal.joinedAt = now
        let batch = db.batch()
        batch.setData(["name": spec.name, "ownerUid": uid, "kind": spec.kind.rawValue,
                       "requireApproval": spec.requireApproval, "icon": cal.icon, "createdAt": now],
                      forDocument: calendar(cal.id))
        batch.setData(["role": "owner", "status": "active", "displayName": spec.displayName,
                       "sharedKeys": spec.sharedKeys, "avatar": spec.avatar, "joinedAt": now],
                      forDocument: member(cal.id, uid))
        batch.setData(["createdBy": uid, "revoked": false, "expiresAt": now + Self.inviteDays * 86_400_000,
                       "calendarName": spec.name, "ownerName": spec.displayName,
                       "kind": spec.kind.rawValue, "requireApproval": spec.requireApproval, "icon": cal.icon],
                      forDocument: calendar(cal.id).collection("invites").document(token))
        batch.setData(Self.indexData(cal), forDocument: index(uid).document(cal.id))
        try await batch.commit()
        return (cal, InviteCode(calendarId: cal.id, token: token))
    }

    private static func indexData(_ cal: SharedCalendar) -> [String: Any] {
        ["name": cal.name, "ownerUid": cal.ownerUid, "kind": cal.kind.rawValue,
         "requireApproval": cal.requireApproval, "icon": cal.icon]
    }

    func joined(uid: String) async throws -> [SharedCalendar] {
        let snap = try await index(uid).getDocuments()
        var out: [SharedCalendar] = []
        for d in snap.documents {
            // 自分の参加の状態は、members の自分の分を見る。消されていたら一覧から外す
            let m = try? await member(d.documentID, uid).getDocument()
            guard let data = m?.data() else { continue }
            let status = MemberStatus(rawValue: data["status"] as? String ?? "") ?? .active
            // 名前・アイコン・許可制は、持ち主が変えるので、本体の最新を読む(読めなければ自分の記録のまま)
            let latest = (try? await calendar(d.documentID).getDocument())?.data() ?? d.data()
            var cal = Self.calendar(id: d.documentID, data: latest, status: status,
                                    sharedKeys: data["sharedKeys"] as? [String] ?? [],
                                    shareManual: data["shareMode"] as? String == "manual")
            cal.joinedAt = (data["joinedAt"] as? NSNumber)?.doubleValue ?? 0
            out.append(cal)
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

    func join(uid: String, code: InviteCode, displayName: String, sharedKeys: [String], avatar: String) async throws -> SharedCalendar {
        let data = try await invite(code)
        let requireApproval = data["requireApproval"] as? Bool ?? false
        let kind = CalendarKind(rawValue: data["kind"] as? String ?? "") ?? .mutual
        let status: MemberStatus = requireApproval ? .pending : .active
        do {
            try await member(code.calendarId, uid).setData([
                "role": "member", "status": status.rawValue, "displayName": displayName,
                // 見せるだけのカレンダーでは、参加者は何も共有しない
                "sharedKeys": kind == .oneway ? [] : sharedKeys,
                "avatar": avatar,
                "joinedAt": Self.nowMillis(), "token": code.token,
            ])
        } catch {
            if Self.isDenied(error) { throw CalendarError.invalidInvite }
            throw error
        }
        var cal = SharedCalendar(id: code.calendarId, name: data["calendarName"] as? String ?? "",
                                 ownerUid: data["createdBy"] as? String ?? "", kind: kind,
                                 requireApproval: requireApproval, status: status,
                                 icon: CalendarIcon.resolved(data["icon"] as? String ?? ""))
        cal.joinedAt = Self.nowMillis()
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
            "calendarName": cal.name, "ownerName": "", "kind": cal.kind.rawValue,
            "requireApproval": cal.requireApproval, "icon": cal.icon,
        ])
        return InviteCode(calendarId: cal.id, token: token)
    }

    func reissueInvite(uid: String, calendar cal: SharedCalendar) async throws -> InviteCode {
        let invites = calendar(cal.id).collection("invites")
        let now = Self.nowMillis()
        let token = InviteCode.random(length: 16)
        let batch = db.batch()
        // いまの招待をすべて無効にして、新しい招待を 1 つ作る
        let active = try await invites.whereField("revoked", isEqualTo: false).getDocuments().documents
        for d in active { batch.updateData(["revoked": true], forDocument: d.reference) }
        batch.setData([
            "createdBy": uid, "revoked": false, "expiresAt": now + Self.inviteDays * 86_400_000,
            "calendarName": cal.name, "ownerName": "", "kind": cal.kind.rawValue,
            "requireApproval": cal.requireApproval, "icon": cal.icon,
        ], forDocument: invites.document(token))
        try await batch.commit()
        return InviteCode(calendarId: cal.id, token: token)
    }

    func leave(uid: String, calendarId: String) async throws {
        try await member(calendarId, uid).delete()
        try await index(uid).document(calendarId).delete()
    }

    func deleteCalendar(calendarId: String, uid: String) async throws {
        let cal = calendar(calendarId)
        // 本体がすでに無い(前の削除が途中で終わって、一覧にだけ残っている)ときは、一覧の記録だけ消す
        if let snap = try? await cal.getDocument(), !snap.exists {
            try await step("一覧") { try await self.index(uid).document(calendarId).delete() }
            return
        }
        // 参加していた人に「削除されました」と知らせるための印を、先に残す(本体が消えたあとでは書けない)
        let calName = (try? await cal.getDocument())?.data()?["name"] as? String ?? ""
        try? await db.collection("deletedCalendars").document(calendarId).setData(["name": calName, "at": Self.nowMillis()])
        // 予定 → 招待 → 参加者 → カレンダー本体の順。持ち主の参加者情報は、予定を消し終えるまで残す必要がある
        for (sub, label) in [("events", "予定"), ("anniversaries", "誕生日・記念日"), ("notices", "お知らせ"), ("invites", "招待"), ("members", "参加者")] {
            try await step(label) {
                // 自分の参加者情報は、本体と同時に消す(先に消すと、本体を消す権限がなくなる)
                let docs = try await cal.collection(sub).getDocuments().documents.filter { !(sub == "members" && $0.documentID == uid) }
                for chunk in stride(from: 0, to: docs.count, by: 400).map({ Array(docs[$0..<min($0 + 400, docs.count)]) }) {
                    let batch = self.db.batch()
                    chunk.forEach { batch.deleteDocument($0.reference) }
                    try await batch.commit()
                }
            }
        }
        try await step("カレンダー本体") {
            let batch = self.db.batch()
            batch.deleteDocument(self.member(calendarId, uid))
            batch.deleteDocument(cal)
            try await batch.commit()
        }
        try await step("一覧") { try await self.index(uid).document(calendarId).delete() }
    }

    /// 削除のどこで失敗したかが分かるように、段階の名前をつけて投げ直す
    private func step(_ label: String, _ body: () async throws -> Void) async throws {
        do {
            try await body()
        } catch {
            throw DeleteStepError(step: label, underlying: error)
        }
    }

    func members(calendarId: String) async throws -> [CalendarMember] {
        let snap = try await calendar(calendarId).collection("members").getDocuments()
        return snap.documents.map { d in
            let x = d.data()
            return CalendarMember(id: d.documentID,
                                  displayName: x["displayName"] as? String ?? "",
                                  isOwner: x["role"] as? String == "owner",
                                  status: MemberStatus(rawValue: x["status"] as? String ?? "") ?? .active,
                                  sharedKeys: x["sharedKeys"] as? [String] ?? [],
                                  avatar: x["avatar"] as? String ?? "",
                                  shareManual: x["shareMode"] as? String == "manual")
        }
        .sorted { ($0.isOwner ? 0 : 1, $0.displayName) < ($1.isOwner ? 0 : 1, $1.displayName) }
    }

    func goneCalendars(uid: String) async -> [GoneCalendar] {
        guard let snap = try? await index(uid).getDocuments() else { return [] }
        var out: [GoneCalendar] = []
        for d in snap.documents {
            // 自分の参加の記録が無くなっていたら、削除されたか、外された。印があれば削除
            guard let m = try? await member(d.documentID, uid).getDocument(), !m.exists else { continue }
            let tomb = try? await db.collection("deletedCalendars").document(d.documentID).getDocument()
            out.append(GoneCalendar(name: d.data()["name"] as? String ?? "", deleted: tomb?.exists == true))
            try? await d.reference.delete()
        }
        return out
    }

    func addNotice(calendarId: String, kind: String, name: String, byUid: String) async throws {
        _ = try await calendar(calendarId).collection("notices").addDocument(data: [
            "kind": kind, "name": name, "byUid": byUid, "at": Self.nowMillis(),
        ])
    }

    func notices(calendarId: String) async throws -> [CalendarNotice] {
        let snap = try await calendar(calendarId).collection("notices").getDocuments()
        return snap.documents.map { d in
            let x = d.data()
            return CalendarNotice(id: d.documentID, kind: x["kind"] as? String ?? "", name: x["name"] as? String ?? "",
                                  byUid: x["byUid"] as? String ?? "", at: (x["at"] as? NSNumber)?.doubleValue ?? 0)
        }
    }

    func setStatus(calendarId: String, uid: String, status: MemberStatus) async throws {
        try await member(calendarId, uid).updateData(["status": status.rawValue])
    }

    func removeMember(calendarId: String, uid: String) async throws {
        try await member(calendarId, uid).delete()
    }

    func listenMyStatus(calendarId: String, uid: String, onChange: @escaping (MemberStatus?) -> Void) -> () -> Void {
        let registration = member(calendarId, uid).addSnapshotListener { snap, _ in
            // 読めなかったとき(通信など)は何も伝えない。文書が無くなったら、参加者から外された
            guard let snap else { return }
            guard snap.exists, let raw = snap.data()?["status"] as? String else { return onChange(nil) }
            onChange(MemberStatus(rawValue: raw))
        }
        return { registration.remove() }
    }

    func listenInfo(calendarId: String, onChange: @escaping (CalendarInfo) -> Void) -> () -> Void {
        let registration = calendar(calendarId).addSnapshotListener { snap, _ in
            // 読めなかったとき(通信・退会したあと)や、消されたカレンダーは何も伝えない(一覧からの片づけは、別の仕組みで行う)
            guard let snap, snap.exists, let data = snap.data() else { return }
            onChange(CalendarInfo(name: data["name"] as? String ?? "",
                                  icon: CalendarIcon.resolved(data["icon"] as? String ?? ""),
                                  requireApproval: data["requireApproval"] as? Bool ?? false))
        }
        return { registration.remove() }
    }

    func updateCalendar(calendarId: String, uid: String, name: String, icon: String, requireApproval: Bool) async throws {
        // 招待には、名前と許可制を写してある(参加の前に見せる・参加の状態を決めるのに使う)ので、同じ内容にそろえる
        let invites = try await calendar(calendarId).collection("invites").getDocuments().documents
        let batch = db.batch()
        batch.updateData(["name": name, "icon": icon, "requireApproval": requireApproval], forDocument: calendar(calendarId))
        for inv in invites {
            batch.updateData(["calendarName": name, "icon": icon, "requireApproval": requireApproval], forDocument: inv.reference)
        }
        batch.setData(["name": name, "icon": icon, "requireApproval": requireApproval], forDocument: index(uid).document(calendarId), merge: true)
        try await batch.commit()
    }

    func updateMine(calendarId: String, uid: String, displayName: String, sharedKeys: [String], avatar: String,
                    shareManual: Bool) async throws {
        try await member(calendarId, uid).updateData(["displayName": displayName, "sharedKeys": sharedKeys, "avatar": avatar,
                                                      "shareMode": shareManual ? "manual" : "auto"])
    }
}

/// 共有カレンダーの削除が、どの段階で失敗したか
private struct DeleteStepError: LocalizedError {
    let step: String
    let underlying: Error

    var errorDescription: String? { "(" + step + ") " + underlying.localizedDescription }
}
