import SwiftUI
import UIKit
import CoreText

enum AppFont {
    static func name(for weight: Font.Weight) -> String {
        if weight == .medium { return "ZenMaruGothic-Medium" }
        if weight == .semibold || weight == .bold || weight == .heavy || weight == .black {
            return "ZenMaruGothic-Bold"
        }
        return "ZenMaruGothic-Regular"
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
