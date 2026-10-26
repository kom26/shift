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
                return UIColor(hue: c.h, saturation: c.s * 0.6, brightness: 0.93, alpha: 1)
            }
            return UIColor(hue: c.h, saturation: min(1, c.s * 1.1 + 0.18), brightness: 0.52, alpha: 1)
        })
    }

    /// カスタム色ピッカー用。画面に見える色(白地に薄塗りした色)で選ばせ、保存は元の色に戻す
    static func pickerBinding(_ hex: Binding<String>) -> Binding<Color> {
        Binding(
            get: { Color(hex: ColorMath.visible(hex.wrappedValue)) },
            set: { hex.wrappedValue = ColorMath.base(fromVisible: $0.toHex()) })
    }

    static func fill(_ hex: String) -> Color {
        Color(UIColor { trait in
            UIColor(Color(hex: hex)).withAlphaComponent(trait.userInterfaceStyle == .dark ? 0.22 : 0.30)
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
    // 週のカードはピンク系、月のカードは薄紫
    static let weekFill = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: "#3a2230")) : UIColor(Color(hex: "#fde9f1")) })
    static let weekText = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: "#f2a6c8")) : UIColor(Color(hex: "#c04a7c")) })
    static let monthFill = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: "#2a2540")) : UIColor(Color(hex: "#efe9fd")) })
    static let monthText = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: "#c9bbf6")) : UIColor(Color(hex: "#6a54c8")) })
    static let deltaUp = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: "#8fd9c3")) : UIColor(Color(hex: "#2c8a73")) })
    static let payFill = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: "#3a3320")) : UIColor(Color(hex: "#fdf3d8")) })
    static let payText = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: "#f7d77b")) : UIColor(Color(hex: "#9a7000")) })
    static let deltaDown = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: "#f19a9a")) : UIColor(Color(hex: "#d9695f")) })
    static let alarm = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: "#f2a64a")) : UIColor(Color(hex: "#e8890c")) })
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

/// 予定バーと同じ塗り(色の薄塗り)で描く色の丸
struct ColorDot: View {
    let hex: String
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(EventColor.fill(hex))
            .background(Circle().fill(Color(.systemBackground)))
            .frame(width: size, height: size)
    }
}
