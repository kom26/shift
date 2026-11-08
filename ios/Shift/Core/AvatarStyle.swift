import UIKit

/// アバターの色・頭文字・写真の読み出し。アプリの UserAvatar とウィジェットで同じ見た目にするため、共通にしてある。
/// avatar の書き方: 空 = 名前の頭文字 / "bg:#rrggbb" = 頭文字の背景色を指定 / "img:" + base64(JPEG) = 写真 / それ以外 = 絵文字
enum AvatarStyle {
    static let palette = ["#6a8cf0", "#e0707a", "#4fae8a", "#d9993d", "#a36ad9", "#4aa3c7", "#c9688f", "#7d8a3a"]
    static let backgroundPrefix = "bg:"
    static let photoPrefix = "img:"

    static func customBackground(_ avatar: String) -> String? {
        avatar.hasPrefix(backgroundPrefix) ? String(avatar.dropFirst(backgroundPrefix.count)) : nil
    }

    /// uid から色を決める(同じ人はいつも同じ色)。端末や起動ごとに変わらない計算にする
    static func color(for uid: String) -> String {
        let sum = uid.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[sum % palette.count]
    }

    static func initial(of name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0) } ?? "?"
    }

    private static let cache = NSCache<NSString, UIImage>()

    /// 写真のアバターなら画像。そうでなければ nil
    static func photo(from avatar: String) -> UIImage? {
        guard avatar.hasPrefix(photoPrefix) else { return nil }
        let key = avatar as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let data = Data(base64Encoded: String(avatar.dropFirst(photoPrefix.count))),
              let img = UIImage(data: data) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }
}
