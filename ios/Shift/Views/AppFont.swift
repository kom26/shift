import SwiftUI
import UIKit
import CoreText

/// 予定バーのフォントの選択肢。丸ゴシック(同梱)のほかは、端末に入っているフォント。
/// 選んだものは UserDefaults に入れて、バーの文字(`Font.bar`)に使う
enum BarFontChoice: String, CaseIterable, Identifiable {
    case zen, gothic, maru, mincho, yu

    static let key = "barFont"

    static var current: BarFontChoice {
        UserDefaults.standard.string(forKey: key).flatMap(BarFontChoice.init(rawValue:)) ?? .zen
    }

    var id: String { rawValue }

    var label: String {
        switch self {
        case .zen: return "丸ゴシック(標準)"
        case .gothic: return "ゴシック"
        case .maru: return "やわらかい丸ゴシック"
        case .mincho: return "明朝"
        case .yu: return "游ゴシック"
        }
    }

    private static func isBold(_ weight: Font.Weight) -> Bool {
        weight == .semibold || weight == .bold || weight == .heavy || weight == .black
    }

    /// 重さに合う、フォントの名前(端末にない名前のときは、システムのフォントに代わる)
    func name(for weight: Font.Weight) -> String {
        let bold = Self.isBold(weight)
        switch self {
        case .zen:
            if weight == .medium { return "ZenMaruGothic-Medium" }
            return bold ? "ZenMaruGothic-Bold" : "ZenMaruGothic-Regular"
        case .gothic: return bold ? "HiraginoSans-W6" : "HiraginoSans-W3"
        case .maru: return "HiraMaruProN-W4"
        case .mincho: return bold ? "HiraMinProN-W6" : "HiraMinProN-W3"
        case .yu: return bold ? "YuGothic-Bold" : "YuGothic-Medium"
        }
    }
}

enum AppFont {
    static func name(for weight: Font.Weight) -> String {
        BarFontChoice.current.name(for: weight)
    }

    /// 同梱TTFを実行時に登録し、UIKit(ナビバー等)にも適用する
    static func register() {
        var urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        if urls.isEmpty {
            urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
        }
        if !urls.isEmpty {
            CTFontManagerRegisterFontsForURLs(urls as CFArray, .process, nil)
        }

    }

}

extension Font {
    /// 予定バー専用の丸ゴシック
    static func bar(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(AppFont.name(for: weight), size: size)
    }

    static func app(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}
