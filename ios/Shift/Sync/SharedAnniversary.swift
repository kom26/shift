import FirebaseFirestore
import Foundation

/// 共有カレンダーの中の、誕生日・記念日 1 件。入れた人(ownerUid)だけが直せる。
/// linked が true のものは、入れた人のアカウントの誕生日と連動する(日付と名前はアカウント設定を変えると変わる)
struct SharedAnniversary: Equatable, Identifiable {
    var id: String
    var ownerUid: String
    var name: String
    var kind: String
    var year: Int?
    var month: Int
    var day: Int
    var monthly: Bool
    var icon: String
    var color: String
    var memo: String
    var linked: Bool

    /// アカウントの誕生日を共有カレンダーに入れたものの ID(1 人 1 件)
    static func linkedId(uid: String) -> String { "birthday_" + uid }

    init(from a: Anniversary, ownerUid: String, linked: Bool) {
        id = a.id
        self.ownerUid = ownerUid
        name = a.name
        kind = a.kind.rawValue
        year = a.year
        month = a.month
        day = a.day
        monthly = a.monthly
        icon = a.icon.rawValue
        color = a.color
        memo = a.memo
        self.linked = linked
    }

    init(id: String, ownerUid: String, name: String, kind: String, year: Int?, month: Int, day: Int,
         monthly: Bool, icon: String, color: String, memo: String, linked: Bool) {
        self.id = id
        self.ownerUid = ownerUid
        self.name = name
        self.kind = kind
        self.year = year
        self.month = month
        self.day = day
        self.monthly = monthly
        self.icon = icon
        self.color = color
        self.memo = memo
        self.linked = linked
    }

    /// 表示用の入れ物(共有カレンダーを開いたときの Store)に入れる形。連動しているものは「自分の誕生日」と同じ扱い(アイコンと色だけ直せる)
    var anniversary: Anniversary {
        var a = Anniversary()
        a.id = id
        a.name = name
        a.kind = Anniversary.Kind(rawValue: kind) ?? .birthday
        a.year = year
        a.month = month
        a.day = day
        a.monthly = monthly
        a.icon = Anniversary.Icon(rawValue: icon) ?? .cake
        a.color = color
        a.memo = memo
        a.isMine = linked ? true : nil
        return a
    }
}

protocol SharedAnniversariesBacking: AnyObject {
    func fetchAnniversaries(calendarId: String) async throws -> [SharedAnniversary]
    /// 変わるたびに、全部が届く。戻り値で購読をやめる
    func listenAnniversaries(calendarId: String, onChange: @escaping ([SharedAnniversary]) -> Void) -> () -> Void
    func setAnniversary(calendarId: String, _ a: SharedAnniversary) async throws
    func deleteAnniversary(calendarId: String, id: String) async throws
}

/// Firestore の `calendars/{id}/anniversaries/{aid}`
final class FirestoreSharedAnniversaries: SharedAnniversariesBacking {
    private var db: Firestore { Firestore.firestore() }
    private func col(_ id: String) -> CollectionReference {
        db.collection("calendars").document(id).collection("anniversaries")
    }

    private static func item(_ d: QueryDocumentSnapshot) -> SharedAnniversary? {
        let x = d.data()
        guard let owner = x["ownerUid"] as? String, let month = (x["month"] as? NSNumber)?.intValue,
              let day = (x["day"] as? NSNumber)?.intValue else { return nil }
        return SharedAnniversary(id: d.documentID, ownerUid: owner, name: x["name"] as? String ?? "",
                                 kind: x["kind"] as? String ?? "birthday", year: (x["year"] as? NSNumber)?.intValue,
                                 month: month, day: day, monthly: x["monthly"] as? Bool ?? false,
                                 icon: x["icon"] as? String ?? "cake", color: x["color"] as? String ?? "#f08a4b",
                                 memo: x["memo"] as? String ?? "", linked: x["linked"] as? Bool ?? false)
    }

    func fetchAnniversaries(calendarId: String) async throws -> [SharedAnniversary] {
        try await col(calendarId).getDocuments().documents.compactMap(Self.item)
    }

    func listenAnniversaries(calendarId: String, onChange: @escaping ([SharedAnniversary]) -> Void) -> () -> Void {
        let registration = col(calendarId).addSnapshotListener { snap, _ in
            guard let snap else { return }
            onChange(snap.documents.compactMap(Self.item))
        }
        return { registration.remove() }
    }

    func setAnniversary(calendarId: String, _ a: SharedAnniversary) async throws {
        var data: [String: Any] = [
            "ownerUid": a.ownerUid, "name": a.name, "kind": a.kind, "month": a.month, "day": a.day,
            "monthly": a.monthly, "icon": a.icon, "color": a.color, "memo": a.memo, "linked": a.linked,
        ]
        if let y = a.year { data["year"] = y }
        try await col(calendarId).document(a.id).setData(data)
    }

    func deleteAnniversary(calendarId: String, id: String) async throws {
        try await col(calendarId).document(id).delete()
    }
}
