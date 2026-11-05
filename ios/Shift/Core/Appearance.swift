import SwiftUI

/// 設定の「外観」。端末の設定に合わせる / ライト / ダーク
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let key = "appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "自動"
        case .light: "ライト"
        case .dark: "ダーク"
        }
    }

    /// nil は端末の設定に従う
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
