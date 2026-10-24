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

/// パステル塗りの上で読める文字色/線色 (明暗で切替)
enum EventColor {
    private static func hsb(_ hex: String) -> (h: CGFloat, s: CGFloat, b: CGFloat) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(Color(hex: hex)).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (h, s, b)
    }

    static func text(_ hex: String) -> Color {
        let c = hsb(hex)
        return Color(UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return UIColor(hue: c.h, saturation: c.s * 0.55, brightness: 0.95, alpha: 1)
            }
            return UIColor(hue: c.h, saturation: min(1, c.s * 1.2 + 0.15), brightness: 0.36, alpha: 1)
        })
    }

    static func line(_ hex: String) -> Color {
        let c = hsb(hex)
        return Color(UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return UIColor(Color(hex: hex))
            }
            return UIColor(hue: c.h, saturation: min(1, c.s * 1.15 + 0.1), brightness: min(1, c.b * 0.82), alpha: 1)
        })
    }
}

enum Theme {
    static let accent = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(Color(hex: "#b9a6f2")) : UIColor(Color(hex: "#7a62d9"))
    })
    static let accentSoft = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(Color(hex: "#2a2540")) : UIColor(Color(hex: "#efe9fd"))
    })
    static let onAccent = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(Color(hex: "#1f1a33")) : UIColor.white
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
