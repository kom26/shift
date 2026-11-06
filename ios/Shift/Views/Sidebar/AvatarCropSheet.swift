import SwiftUI

/// 共有カレンダーのアイコンを選ぶ(6 つずつ 2 段)
struct CalendarIconPicker: View {
    @Binding var selection: String
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(CalendarIcon.choices, id: \.name) { item in
                let on = selection == item.name
                Button { selection = item.name } label: {
                    Image(systemName: item.name)
                        .font(.system(size: 20))
                        .foregroundStyle(on ? Theme.onAccent : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(on ? Theme.accent : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

/// 写真を選んだあとに、アイコンにする範囲を合わせる。ピンチで拡大・縮小、2 本指で回転、ドラッグで位置。
/// 円の内側がアイコンになる(切り取るのは、その円がぴったり入る正方形)
struct AvatarCropTarget: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct AvatarCropSheet: View {
    let image: UIImage
    /// 範囲を合わせた正方形の画像(AvatarPhoto.side 四方)
    let onDone: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var angle: Angle = .zero
    @State private var offset: CGSize = .zero
    @State private var boxSide: CGFloat = 300
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var twist: Angle = .zero
    @GestureState private var drag: CGSize = .zero

    private static let maxScale: CGFloat = 6

    /// 写真の短い辺が、ちょうど正方形に収まる倍率
    private func fit(_ box: CGFloat) -> CGFloat {
        box / max(1, min(image.size.width, image.size.height))
    }

    private func clamped(_ s: CGFloat) -> CGFloat { min(max(s, 1), Self.maxScale) }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let box = max(200, min(geo.size.width - 32, geo.size.height - 120, 380))
                VStack(spacing: 16) {
                    Spacer(minLength: 0)
                    ZStack {
                        Color.black
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: image.size.width * fit(box), height: image.size.height * fit(box))
                            .scaleEffect(clamped(scale * pinch))
                            .rotationEffect(angle + twist)
                            .offset(x: offset.width + drag.width, y: offset.height + drag.height)
                        // 円の外を暗くして、アイコンになる範囲を見せる
                        CircleHole()
                            .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                            .allowsHitTesting(false)
                        Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                            .allowsHitTesting(false)
                    }
                    .frame(width: box, height: box)
                    .clipShape(Rectangle())
                    .contentShape(Rectangle())
                    .gesture(gestures)
                    Text("ピンチで拡大・縮小、2 本指で回転、ドラッグで位置を合わせます")
                        .font(.app(12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .onAppear { boxSide = box }
                .onChange(of: box) { _, new in boxSide = new }
            }
            .navigationTitle("アイコンの範囲")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        onDone(render(box: boxSide))
                        dismiss()
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("位置を戻す") {
                        withAnimation(.snappy) {
                            scale = 1
                            angle = .zero
                            offset = .zero
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color(.systemBackground))
    }

    private var gestures: some Gesture {
        let move = DragGesture()
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                offset = CGSize(width: offset.width + value.translation.width,
                                height: offset.height + value.translation.height)
            }
        let zoom = MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { value in scale = clamped(scale * value.magnification) }
        let turn = RotateGesture()
            .updating($twist) { value, state, _ in state = value.rotation }
            .onEnded { value in angle += value.rotation }
        return move.simultaneously(with: zoom).simultaneously(with: turn)
    }

    /// 見えている範囲と同じ見た目で、AvatarPhoto.side 四方の画像に描く
    private func render(box: CGFloat) -> UIImage {
        let out = AvatarPhoto.side
        let k = out / max(1, box)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: out, height: out))
            let cg = ctx.cgContext
            cg.translateBy(x: out / 2 + offset.width * k, y: out / 2 + offset.height * k)
            cg.rotate(by: CGFloat(angle.radians))
            let s = fit(box) * clamped(scale) * k
            cg.scaleBy(x: s, y: s)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2,
                                  width: image.size.width, height: image.size.height))
        }
    }
}

/// 四角から円をくり抜いた形(円の外側だけを塗る)
private struct CircleHole: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        p.addEllipse(in: rect)
        return p
    }
}
