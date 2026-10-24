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
        configureAppearance()
    }

    private static func configureAppearance() {
        if let bold = UIFont(name: "ZenMaruGothic-Bold", size: 17) {
            UINavigationBar.appearance().titleTextAttributes = [.font: bold]
        }
        if let large = UIFont(name: "ZenMaruGothic-Bold", size: 34) {
            UINavigationBar.appearance().largeTitleTextAttributes = [.font: large]
        }
        if let regular = UIFont(name: "ZenMaruGothic-Regular", size: 17) {
            UIBarButtonItem.appearance().setTitleTextAttributes([.font: regular], for: .normal)
        }
    }
}

extension Font {
    static func app(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(AppFont.name(for: weight), size: size)
    }
}
