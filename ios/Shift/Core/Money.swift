import Foundation

enum Money {
    /// 円単位に四捨五入し、¥ とカンマ区切りで返す
    static func yen(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "ja_JP")
        f.groupingSeparator = ","
        f.maximumFractionDigits = 0
        let r = value.rounded()
        return "¥" + (f.string(from: NSNumber(value: r)) ?? String(Int(r)))
    }
}
