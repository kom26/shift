import SwiftUI

/// 開始・締切の矢印形のタグの輪郭。開始は右向き、締切は左向き
struct ArrowTagShape: Shape {
    let pointsRight: Bool
    var notch: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let n = min(notch, rect.width / 2)
        if pointsRight {
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - n, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX - n, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.minX + n, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + n, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        }
        p.closeSubpath()
        return p
    }
}

/// 開始と締切をつなぐ点線。長さに合わせて点の間隔を決めて、両端に点が来るようにする
enum TaskDots {
    static let radius: CGFloat = 0.75
    static let targetSpacing: CGFloat = 3.6

    /// x1〜x2 のあいだに、点を等間隔に並べる(点の数は、間隔が 3.6pt に近くなるように決める)。
    /// 最初の点が x1、最後の点が x2 にぴったり来るので、タグの先からの余白が、左右で同じになる
    static func centers(x1: CGFloat, x2: CGFloat) -> [CGFloat] {
        let length = x2 - x1
        guard length > 0 else { return [] }
        let n = max(1, Int((length / targetSpacing).rounded()))
        let step = length / CGFloat(n)
        return (0...n).map { x1 + CGFloat($0) * step }
    }

    /// 点(小さな丸)の線。色は、`.fill` で付ける
    static func path(x1: CGFloat, x2: CGFloat, y: CGFloat) -> Path {
        var p = Path()
        for x in centers(x1: x1, x2: x2) {
            p.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }
        return p
    }
}
