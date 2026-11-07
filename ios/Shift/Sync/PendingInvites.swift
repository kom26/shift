import Foundation

/// アカウント登録の前に開いた招待(QR・リンク)。登録が済んだら、上から順に参加の確認を開く
struct PendingInvite: Codable, Identifiable, Equatable {
    var code: String
    /// 共有カレンダーの名前(まだ分からなければ空)
    var name: String
    var id: String { code }

    static func decode(_ json: String) -> [PendingInvite] {
        (try? JSONDecoder().decode([PendingInvite].self, from: Data(json.utf8))) ?? []
    }

    static func encode(_ list: [PendingInvite]) -> String {
        (try? JSONEncoder().encode(list)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
