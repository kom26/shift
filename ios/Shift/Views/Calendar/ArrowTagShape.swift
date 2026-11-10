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
    static func style(length: CGFloat) -> StrokeStyle {
        let n = max(1, Int((length / 3.6).rounded()))
        let step = length / CGFloat(n)
        return StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.1, max(0.1, step - 0.1)])
    }
}
