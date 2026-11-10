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

/// 月表示・週表示(終日の場所)の、開始・締切のタグ。開始は白抜きの右向き、締切は塗りの左向き。幅は予定のバーと同じ(1 マス)
struct TaskTagBar: View {
    @Environment(\.calendarBackground) private var calBg
    let title: String
    let color: String
    let isStart: Bool
    let height: CGFloat
    var fontSize: CGFloat = 10

    var body: some View {
        let shape = ArrowTagShape(pointsRight: isStart)
        Text(title)
            .font(.bar(fontSize, weight: .bold))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(EventColor.text(color))
            .padding(.leading, isStart ? 4 : 8)
            .padding(.trailing, isStart ? 8 : 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .background(isStart ? calBg : EventColor.fill(color), in: shape)
            .background(calBg, in: shape)
            .overlay { if isStart { shape.stroke(Color(hex: color), lineWidth: 1.2) } }
            .clipShape(shape)
    }
}

/// 開始・締切の種類を表す小さな記号(週表示の線の文字、予定一覧など)
struct TaskKindMark: View {
    let isStart: Bool
    var body: some View {
        Image(systemName: isStart ? "play.fill" : "flag.fill")
    }
}

/// 月表示で、開始から締切までを 1 本につないだもの。両端が矢印のタグ(開始は右向き・締切は左向き)で、間は点線。
/// 週をまたぐときは、その週の中の端だけタグを出す
struct TaskLinkBar: View {
    let title: String
    let color: String
    /// 何マスぶんの幅か
    let span: Int
    let showsStart: Bool
    let showsDue: Bool
    let height: CGFloat
    var fontSize: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let cellW = max(1, (geo.size.width + 2) / CGFloat(max(1, span)))
            let tagW = max(0, cellW - 2)
            let x1 = showsStart ? cellW : 0
            let x2 = showsDue ? geo.size.width - cellW : geo.size.width
            ZStack(alignment: .topLeading) {
                if x2 > x1 {
                    Path { p in
                        p.move(to: CGPoint(x: x1 + 2, y: geo.size.height / 2))
                        p.addLine(to: CGPoint(x: x2 - 2, y: geo.size.height / 2))
                    }
                    .stroke(Color(hex: color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.1, 3.5]))
                }
                if showsStart {
                    TaskTagBar(title: title, color: color, isStart: true, height: height, fontSize: fontSize)
                        .frame(width: tagW, height: height)
                }
                if showsDue {
                    TaskTagBar(title: title, color: color, isStart: false, height: height, fontSize: fontSize)
                        .frame(width: tagW, height: height)
                        .offset(x: geo.size.width - tagW)
                }
            }
        }
        .frame(height: height)
    }
}
