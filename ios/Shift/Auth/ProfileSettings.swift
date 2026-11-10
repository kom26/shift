import Foundation
import Observation

/// アプリの中で使う、自分の名前とアバター。アカウントの連携で決まる名前を、自分で付け直せる。
/// 共有カレンダーを作る・参加するときの、「相手に見える名前」と「アバター」の初期値になる(この端末に保存する)
@MainActor
@Observable
final class ProfileSettings {
    private static let nameKey = "profile-name"
    private static let avatarKey = "profile-avatar"

    @ObservationIgnored private let defaults: UserDefaults

    /// 自分で付けた名前。空なら、連携してきた名前を使う
    var customName: String {
        didSet { defaults.set(customName, forKey: Self.nameKey) }
    }

    /// アバター。空なら名前の頭文字、`img:` で始まれば写真
    var avatar: String {
        didSet { defaults.set(avatar, forKey: Self.avatarKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        customName = defaults.string(forKey: Self.nameKey) ?? ""
        avatar = defaults.string(forKey: Self.avatarKey) ?? ""
    }

    /// 端末の設定が入れ替わったあと(アカウントから戻したとき、ログアウトで消したとき)に、読み直す
    func reload() {
        customName = defaults.string(forKey: Self.nameKey) ?? ""
        avatar = defaults.string(forKey: Self.avatarKey) ?? ""
    }

    /// アプリの中での名前。自分で付けていればそれ。なければ、連携してきた名前(なければメールの手前の部分)
    func displayName(for account: AuthService.Account?) -> String {
        let custom = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        return Self.providerName(account)
    }

    /// 連携してきた名前
    static func providerName(_ account: AuthService.Account?) -> String {
        if let name = account?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        if let email = account?.email, let local = email.split(separator: "@").first { return String(local) }
        return ""
    }
}
