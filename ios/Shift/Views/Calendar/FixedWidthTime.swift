import SwiftUI
import UIKit

/// バーの時刻表示。フォントはそのままに、数字を一番広い数字の幅の枠に入れて、
/// どの時刻でも「00:00-00:00」と同じ横幅にそろえる
enum FixedWidthTime {
    /// 幅をそろえる基準の文字列
    static let widest = "00:00-00:00"

    private static var cache: [String: CGFloat] = [:]

    /// 1文字ぶんの枠の幅(文字サイズ 1pt あたり)。数字はどれも同じ幅になる
    static func cell(_ ch: Character, weight: Font.Weight) -> CGFloat {
        let name = AppFont.name(for: weight)
        let isDigit = ch.isASCII && ch.isNumber
        let key = name + (isDigit ? "#" : String(ch))
        if let w = cache[key] { return w }
        let font = UIFont(name: name, size: 100) ?? .systemFont(ofSize: 100)
        let chars = isDigit ? Array("0123456789") : [ch]
        let w = chars.map { (String($0) as NSString).size(withAttributes: [.font: font]).width / 100 }.max() ?? 0
        cache[key] = w
        return w
    }

    static func width(of text: String, size: CGFloat, weight: Font.Weight = .bold) -> CGFloat {
        text.reduce(0) { $0 + cell($1, weight: weight) } * size
    }

    /// 横幅 avail に「00:00-00:00」がちょうど収まる文字サイズ
    static func fitSize(width avail: CGFloat, weight: Font.Weight = .bold) -> CGFloat {
        let perPoint = width(of: widest, size: 1, weight: weight)
        return perPoint > 0 ? avail / perPoint : 9
    }
}

struct FixedWidthTimeText: View {
    let text: String
    let size: CGFloat
    var weight: Font.Weight = .bold
    /// 指定すると、入り切らないときに末尾を削って「…」にする
    var maxWidth: CGFloat? = nil

    private var shown: String {
        guard let m = maxWidth, FixedWidthTime.width(of: text, size: size, weight: weight) > m else { return text }
        var t = text
        while !t.isEmpty, FixedWidthTime.width(of: t + "…", size: size, weight: weight) > m { t.removeLast() }
        return t + "…"
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, ch in
                Text(String(ch))
                    .font(.bar(size, weight: weight))
                    .frame(width: FixedWidthTime.cell(ch, weight: weight) * size)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
