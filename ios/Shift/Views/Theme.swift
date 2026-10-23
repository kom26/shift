import SwiftUI
import UIKit

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    func toHex() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x", Int((max(0, min(1, r)) * 255).rounded()), Int((max(0, min(1, g)) * 255).rounded()), Int((max(0, min(1, b)) * 255).rounded()))
    }
}

enum Theme {
    static let accent = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(Color(hex: "#818cf8")) : UIColor(Color(hex: "#4f46e5"))
    })
    static let accentSoft = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(Color(hex: "#1e1d3a")) : UIColor(Color(hex: "#eef2ff"))
    })
    static let saturday = Color(hex: "#3b82f6")
    static let sunday = Color(hex: "#ef4444")
}

extension DayType {
    var color: Color {
        switch self {
        case .normal: return Color.secondary
        case .saturday: return Theme.saturday
        case .sunday, .holiday: return Theme.sunday
        }
    }
}
