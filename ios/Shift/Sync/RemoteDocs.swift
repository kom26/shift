import Foundation

/// アカウントに保存するデータの種類。1 件ずつ別のドキュメントとして置く
enum SyncCollection: String, CaseIterable {
    case events, workplaces, favorites, anniversaries, settings
}

/// クラウド上の 1 件。中身(payload)は JSON 文字列のまま持つ
struct RemoteDoc: Equatable {
    let id: String
    let payload: String
    /// 最後に変更した時刻(秒)。新しいほうが勝つ
    let updatedAt: Double
    /// 削除済みの印。消さずに残すことで、別の端末で消した予定が復活しない
    let deleted: Bool
    /// 職場・よく使う予定の並び順
    let order: Int
}

/// クラウドの入れ物(テストでは差し替える)
protocol RemoteDocs: AnyObject {
    func fetchAll(uid: String) async throws -> [SyncCollection: [RemoteDoc]]
    func set(uid: String, collection: SyncCollection, doc: RemoteDoc)
    /// 変わったドキュメントが届くたびに onDocs を呼ぶ。戻り値で購読をやめる
    func listen(uid: String, collection: SyncCollection, onDocs: @escaping ([RemoteDoc]) -> Void) -> () -> Void
    func deleteAll(uid: String) async throws
}
