import FirebaseAuth
import FirebaseStorage
import Foundation

/// 付けた画像の、クラウド側の置き場(Firebase Storage の users/<uid>/attachments/<id>.jpg)。
/// 端末で選んだ画像を送り、ほかの端末では、見るときに取ってくる。使わなくなった画像は、定期的に片づける。
/// ログインしていないときは何もしない(端末の中だけで使える)
enum AttachmentCloud {
    private static let uploadedKey = "attachmentsUploaded"
    /// この日数より新しい画像は、片づけない(ほかの端末の予定がまだ届いていないだけかもしれないため)
    static let pruneGraceDays = 3

    private static var uid: String? { Auth.auth().currentUser?.uid }

    /// 共有カレンダーの画像は calendars/<カレンダーID>/attachments、自分の画像は users/<uid>/attachments に置く
    private static func reference(_ id: String, uid: String) -> StorageReference {
        if let cid = AttachmentStore.calendarId(of: id) {
            return Storage.storage().reference().child("calendars/\(cid)/attachments/\(id).jpg")
        }
        return Storage.storage().reference().child("users/\(uid)/attachments/\(id).jpg")
    }

    private static var uploaded: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: uploadedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: uploadedKey) }
    }

    /// 端末にある画像を送る(送れなかったときは、あとの片づけのときに、もう一度送る)
    static func upload(_ id: String) async {
        guard let uid, let data = AttachmentStore.data(id), !uploaded.contains(id) else { return }
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"
        do {
            _ = try await reference(id, uid: uid).putDataAsync(data, metadata: meta)
            uploaded.insert(id)
        } catch {}
    }

    /// 端末にない画像を、クラウドから取ってくる。取れたら true
    static func download(_ id: String) async -> Bool {
        guard let uid else { return false }
        do {
            let data = try await reference(id, uid: uid).data(maxSize: 6 * 1024 * 1024)
            AttachmentStore.write(data, id: id)
            uploaded.insert(id)
            return true
        } catch {
            return false
        }
    }

    /// 端末と、クラウドから消す
    static func remove(_ id: String) async {
        AttachmentStore.delete(id)
        guard let uid else { return }
        try? await reference(id, uid: uid).delete()
        uploaded.remove(id)
    }

    /// 片づけ。どの予定・開始締切からも使われていない画像のうち、作ってから日がたったものを消し、
    /// 端末にあってまだ送っていない、使われている画像は送る
    static func sweep(referenced: Set<String>) async {
        guard let uid else { return }
        for id in referenced where AttachmentStore.exists(id) { await upload(id) }
        let cutoff = Date().addingTimeInterval(-Double(pruneGraceDays) * 86_400)
        // 端末の中
        // 共有カレンダーの画像は、端末のキャッシュなので、ここでは片づけない
        for (id, created) in AttachmentStore.localFiles()
        where !referenced.contains(id) && created < cutoff && AttachmentStore.calendarId(of: id) == nil {
            AttachmentStore.delete(id)
        }
        // クラウドの中
        guard let list = try? await Storage.storage().reference().child("users/\(uid)/attachments").listAll() else { return }
        for item in list.items {
            let id = (item.name as NSString).deletingPathExtension
            guard !referenced.contains(id),
                  let meta = try? await item.getMetadata(), let created = meta.timeCreated, created < cutoff else { continue }
            try? await item.delete()
            uploaded.remove(id)
        }
    }
}
