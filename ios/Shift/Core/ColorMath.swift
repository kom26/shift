import Foundation

/// 予定の色は元の色を 30% の濃さで白地に塗って表示する。表示色と元の色の相互変換
enum ColorMath {
    static let alpha = 0.30

    private static func channels(_ hex: String) -> [Double]? {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return [Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF)]
    }

    private static func hex(_ c: [Double]) -> String {
        let v = c.map { Int(max(0, min(255, $0)).rounded()) }
        return String(format: "#%02x%02x%02x", v[0], v[1], v[2])
    }

    /// 元の色を白地に薄塗りした見た目の色
    static func visible(_ base: String) -> String {
        guard let c = channels(base) else { return base }
        return hex(c.map { $0 * alpha + 255 * (1 - alpha) })
    }

    /// 見た目の色から元の色を求める(濃すぎて表せない成分は 0 に丸める)
    static func base(fromVisible v: String) -> String {
        guard let c = channels(v) else { return v }
        return hex(c.map { ($0 - 255 * (1 - alpha)) / alpha })
    }
}
