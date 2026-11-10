import PhotosUI
import SwiftUI

/// 共有カレンダーのアイコンを選ぶ(6 つずつ 2 段)
struct CalendarIconPicker: View {
    @Binding var selection: String
    /// 選んだあとの動き(選ぶ画面を閉じるなど)
    var onPick: () -> Void = {}
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(CalendarIcon.choices, id: \.name) { item in
                let on = CalendarIcon.split(selection).name == item.name
                let tint = CalendarIcon.split(selection).color.map { Color(hex: $0) } ?? Theme.accent
                Button {
                    selection = CalendarIcon.join(name: item.name, color: CalendarIcon.split(selection).color)
                    onPick()
                } label: {
                    // 選んだ色が、その場で、アイコンの一覧にも出る(選んでいるアイコンは、色の下地つき)
                    Image(systemName: item.name)
                        .font(.system(size: 20))
                        .foregroundStyle(tint)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(on ? tint.opacity(0.25) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint, lineWidth: on ? 2 : 0))
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

/// 共有カレンダーのアイコン。写真なら丸く切り取って、記号なら、そのまま出す(ドロワー・帯の小さい表示用)
struct CalendarIconView: View {
    let icon: String
    var size: CGFloat = 24

    var body: some View {
        if let photo = AvatarPhoto.image(from: icon) {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            let (name, color) = CalendarIcon.split(icon)
            if let color {
                Image(systemName: name).foregroundStyle(Color(hex: color)).frame(width: size)
            } else {
                Image(systemName: name).frame(width: size)
            }
        }
    }
}

/// 予定の行につける、共有カレンダーのアイコン(丸)。写真ならそのまま、記号なら色つきの丸の中に出す
struct CalendarBadge: View {
    let icon: String
    var size: CGFloat = 28

    var body: some View {
        if let photo = AvatarPhoto.image(from: icon) {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            let (name, color) = CalendarIcon.split(icon)
            Image(systemName: name)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(color.map { Color(hex: $0) } ?? Theme.accent)
                .frame(width: size, height: size)
                .background(Circle().fill(color.map { Color(hex: $0).opacity(0.2) } ?? Theme.accentSoft))
        }
    }
}

/// カレンダー名の入力。左のアイコンをタップすると、アイコンを選び直せる(記号、または写真)
struct CalendarNameField: View {
    @Binding var name: String
    @Binding var icon: String
    @State private var picking = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var cropTarget: AvatarCropTarget?
    @State private var loadFailed = false
    @Environment(Store.self) private var store

    /// アイコンの色。まだ決めていないときは、いつもの紫
    private var iconColor: Binding<String> {
        Binding(
            get: { CalendarIcon.split(icon).color ?? "#7a62d9" },
            set: { icon = CalendarIcon.join(name: CalendarIcon.split(icon).name, color: $0) })
    }

    var body: some View {
        HStack(spacing: 12) {
            Button { picking = true } label: {
                Group {
                    if CalendarIcon.isPhoto(icon) {
                        CalendarBadge(icon: icon, size: 44)
                    } else {
                        let (name, color) = CalendarIcon.split(icon)
                        let tint = color.map { Color(hex: $0) } ?? Theme.accent
                        Image(systemName: name)
                            .font(.system(size: 20))
                            .foregroundStyle(tint)
                            .frame(width: 44, height: 44)
                            .background(tint.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("アイコンを変える")
            .popover(isPresented: $picking) {
                VStack(alignment: .leading, spacing: 12) {
                    CalendarIconPicker(selection: $icon)
                    if !CalendarIcon.isPhoto(icon) {
                        // アイコンの色(参加者全員に同じ色で見える)。予定の色と同じ、決まった色と好きな色
                        ColorRow(color: iconColor, recent: store.customColors, onDeleteRecent: { store.removeCustomColor($0) },
                                 iconName: CalendarIcon.split(icon).name)
                    }
                    Button {
                        picking = false
                        // ポップオーバーが閉じてから、写真の選択を開く
                        Task {
                            try? await Task.sleep(for: .milliseconds(350))
                            showPhotoPicker = true
                        }
                    } label: {
                        Label("写真から選ぶ", systemImage: "photo")
                            .font(.app(15, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    // アイコンと色を選び終えたら、ここで閉じる(外をタップしても閉じるが、気づきにくい)
                    Button { picking = false } label: {
                        Text("完了")
                            .font(.app(16, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .frame(width: 320)
                .presentationCompactAdaptation(.popover)
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        cropTarget = AvatarCropTarget(image: image)
                    } else {
                        loadFailed = true
                    }
                    photoItem = nil
                }
            }
            .sheet(item: $cropTarget) { target in
                AvatarCropSheet(image: target.image) { square in
                    if let encoded = AvatarPhoto.encode(square: square) { icon = encoded }
                }
            }
            .alert("写真を読み込めませんでした", isPresented: $loadFailed) { Button("OK") {} }
            TextField("カレンダー名", text: $name)
        }
    }
}
