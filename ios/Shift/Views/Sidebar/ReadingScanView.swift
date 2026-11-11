import SwiftUI
import UIKit
import Vision

/// 画像の中の、文字らしい場所(0〜1 の割合。左上が原点)を、端末の中で探す。通信は使わない
enum TextRegions {
    static func detect(in image: UIImage) async -> [CGRect] {
        guard let cg = image.cgImage else { return [] }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNDetectTextRectanglesRequest()
                request.reportCharacterBoxes = false
                let handler = VNImageRequestHandler(cgImage: cg, orientation: Self.orientation(image.imageOrientation), options: [:])
                try? handler.perform([request])
                let rects = (request.results ?? []).compactMap { obs -> CGRect? in
                    let b = obs.boundingBox
                    // 小さすぎるものは、ゴミなので捨てる。Vision は左下が原点なので、左上が原点に直す
                    guard b.width > 0.015, b.height > 0.004 else { return nil }
                    return CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
                }
                cont.resume(returning: Array(rects.prefix(200)))
            }
        }
    }

    private static func orientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

/// 並べ方(縦横比を保って、横一列に並べる)。高さは、全部の画像が使える幅に収まる高さと、最大の高さの、小さいほう
enum ScanLayout {
    static let maxHeight: CGFloat = 260
    static let gap: CGFloat = 10

    static func size(aspects: [CGFloat], availableWidth: CGFloat) -> (height: CGFloat, widths: [CGFloat]) {
        let sum = max(0.01, aspects.reduce(0, +))
        let height = min(maxHeight, (availableWidth - gap * CGFloat(max(0, aspects.count - 1))) / sum)
        return (height, aspects.map { $0 * height })
    }

    /// 線の位置(0〜1)。往復して、出だしと終わりで、ゆっくり動く
    static func beamPosition(time t: Double, index: Int) -> CGFloat {
        let dur = 2.2 + 0.25 * Double(index % 3)
        let u = (t / dur + Double(index) * 0.23).truncatingRemainder(dividingBy: 2)
        let p = u < 1 ? u : 2 - u
        return CGFloat(0.5 - cos(Double.pi * p) / 2)
    }
}

/// 「読み取っています」の画面の、画像の部分。アップロードした画像を横に並べて、光の線が上下に往復する。
/// 画像の中の文字は、線が通る一瞬、ぱっと光って、そのあとも、淡い枠として残る(認識した文字が、増えていく)
struct ReadingScanView: View {
    let images: [UIImage]
    @State private var regions: [[CGRect]] = []
    @State private var seen = SeenState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 認識した文字(画像ごとに、何番目の文字か)。描画のたびに更新するので、参照型で持つ
    final class SeenState {
        var seen: [Set<Int>] = []
    }

    var body: some View {
        GeometryReader { geo in
            let aspects = images.map { $0.size.height > 0 ? $0.size.width / $0.size.height : 1 }
            let layout = ScanLayout.size(aspects: aspects, availableWidth: geo.size.width)
            HStack(spacing: ScanLayout.gap) {
                ForEach(images.indices, id: \.self) { i in
                    tile(i, width: layout.widths[i], height: layout.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: ScanLayout.maxHeight)
        .task {
            // 文字の位置は、画像ごとに、端末の中で探す(読み取りの通信とは別。見つかった画像から、光り始める)
            regions = Array(repeating: [], count: images.count)
            seen.seen = Array(repeating: [], count: images.count)
            for (i, image) in images.enumerated() {
                let found = await TextRegions.detect(in: image)
                if i < regions.count { regions[i] = found }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("読み取り中の画像")
    }

    private func tile(_ i: Int, width: CGFloat, height: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        return ZStack {
            Image(uiImage: images[i]).resizable().frame(width: width, height: height)
            if reduceMotion {
                // 動きを減らす設定: 線は動かさない。認識した文字を、淡い枠で出すだけ
                Canvas { ctx, size in drawText(&ctx, size: size, index: i, beam: nil) }
            } else {
                TimelineView(.animation) { timeline in
                    Canvas { ctx, size in
                        let beam = ScanLayout.beamPosition(time: timeline.date.timeIntervalSinceReferenceDate, index: i)
                        drawText(&ctx, size: size, index: i, beam: beam)
                        drawBeam(&ctx, size: size, position: beam)
                    }
                }
            }
            corners
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color(.separator).opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 9, y: 4)
    }

    /// 文字の枠。線が通る一瞬は、ぱっと光り、そのあとは、淡い枠として残る(`beam` が nil なら、全部、淡い枠)
    private func drawText(_ ctx: inout GraphicsContext, size: CGSize, index i: Int, beam: CGFloat?) {
        guard i < regions.count, i < seen.seen.count else { return }
        let color = Theme.accent
        for (k, r) in regions[i].enumerated() {
            let rect = CGRect(x: r.minX * size.width, y: r.minY * size.height, width: r.width * size.width, height: r.height * size.height)
            var opacity: CGFloat = 0
            if let beam {
                let center = r.midY
                let dist = abs(beam - center)
                if dist < 0.03 { seen.seen[i].insert(k) }
                let d = dist / 0.055
                let flash = d >= 1 ? 0 : pow(1 - d, 1.6)
                opacity = max(seen.seen[i].contains(k) ? 0.5 : 0, flash)
            } else {
                opacity = 0.5
            }
            guard opacity > 0.01 else { continue }
            let path = Path(roundedRect: rect, cornerRadius: 2)
            ctx.fill(path, with: .color(color.opacity(0.34 * opacity)))
            ctx.stroke(path, with: .color(color.opacity(0.55 * opacity)), lineWidth: 1)
        }
    }

    /// 光の線。画像の幅いっぱいで、左右の端も、同じ濃さ。白っぽい光は、真ん中だけ。周りに、にじむ光
    private func drawBeam(_ ctx: inout GraphicsContext, size: CGSize, position p: CGFloat) {
        let y = p * size.height
        let color = Theme.accent
        let line = CGRect(x: 0, y: y - 1, width: size.width, height: 2)
        var glow = ctx
        glow.addFilter(.shadow(color: color.opacity(0.55), radius: 6, x: 0, y: 0))
        glow.addFilter(.shadow(color: color.opacity(0.28), radius: 18, x: 0, y: 0))
        let gradient = Gradient(stops: [
            .init(color: color.opacity(0.85), location: 0),
            .init(color: color.opacity(0.85), location: 0.38),
            .init(color: Color.white.opacity(0.6), location: 0.5),
            .init(color: color.opacity(0.85), location: 0.62),
            .init(color: color.opacity(0.85), location: 1),
        ])
        glow.fill(Path(line), with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: y), endPoint: CGPoint(x: size.width, y: y)))
    }

    /// 四隅の、小さな角の枠
    private var corners: some View {
        GeometryReader { geo in
            Path { p in
                let l: CGFloat = 10, m: CGFloat = 5
                let w = geo.size.width, h = geo.size.height
                for (cx, cy, dx, dy) in [(m, m, 1.0, 1.0), (w - m, m, -1.0, 1.0), (m, h - m, 1.0, -1.0), (w - m, h - m, -1.0, -1.0)] {
                    p.move(to: CGPoint(x: cx + dx * l, y: cy))
                    p.addLine(to: CGPoint(x: cx, y: cy))
                    p.addLine(to: CGPoint(x: cx, y: cy + dy * l))
                }
            }
            .stroke(Theme.accent.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
    }
}
