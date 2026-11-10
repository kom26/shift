import PhotosUI
import SwiftUI
import UIKit

/// 予定・開始締切に付ける画像の置き場。この端末の書類フォルダに、縮小した JPEG で入れる(他の端末には同期しない)
enum AttachmentStore {
    private static var directory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "attachments")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(_ id: String) -> URL { directory.appending(path: "\(id).jpg") }

    /// 長い辺 1600px までに縮めて保存し、名前を返す
    static func save(_ data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > 1600 ? 1600 / longest : 1
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let jpeg = UIGraphicsImageRenderer(size: size, format: format)
            .jpegData(withCompressionQuality: 0.75) { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        let id = UUID().uuidString
        do {
            try jpeg.write(to: fileURL(id), options: .atomic)
            return id
        } catch {
            return nil
        }
    }

    static func image(_ id: String) -> UIImage? { UIImage(contentsOfFile: fileURL(id).path) }

    static func delete(_ id: String) { try? FileManager.default.removeItem(at: fileURL(id)) }
}

enum AttachmentLink {
    /// 入力された URL を開ける形にする。http(s) の頭が無ければ付ける。空や、URL にならない文字は nil
    static func destination(_ text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(" ") else { return nil }
        let full = t.lowercased().hasPrefix("http://") || t.lowercased().hasPrefix("https://") ? t : "https://" + t
        guard let url = URL(string: full), url.host?.contains(".") == true else { return nil }
        return url
    }
}

/// 付けた画像を大きく見る画面。タップか「閉じる」で戻る
struct AttachmentImageViewer: View {
    let imageId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let image = AttachmentStore.image(imageId) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("この端末には画像がありません")
                    .font(.app(14))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.2), in: Circle())
                    .padding(16)
            }
            .accessibilityLabel("閉じる")
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
    }
}

/// 編集画面の「+ メモ  + 画像  + URL」のチップと、押すと開く欄。Form の中に置く。
/// 空のまま別のチップを押す、または欄の外をタップすると、空の欄は閉じる。中身がある欄は開いたまま
struct AttachmentFields: View {
    @Binding var memo: String
    /// 空は無し
    @Binding var url: String
    @Binding var imageId: String?
    /// 親の Form が、タップのたびに増やす数。増えたら「欄の外をタップした」として、空の欄を閉じる
    var outsideTap: Int

    private enum Kind: Hashable { case memo, image, url }

    @State private var openKinds: Set<Kind> = []
    @State private var imageEditing = false
    @State private var urlEditing = false
    @State private var showViewer = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showPicker = false
    @State private var lastTouch: (kind: Kind, at: Date)?
    @FocusState private var focus: Kind?

    init(memo: Binding<String>, url: Binding<String>, imageId: Binding<String?>, outsideTap: Int) {
        _memo = memo
        _url = url
        _imageId = imageId
        self.outsideTap = outsideTap
        var open = Set<Kind>()
        if !memo.wrappedValue.isEmpty { open.insert(.memo) }
        if imageId.wrappedValue != nil { open.insert(.image) }
        if !url.wrappedValue.isEmpty { open.insert(.url) }
        _openKinds = State(initialValue: open)
    }

    private func has(_ kind: Kind) -> Bool {
        switch kind {
        case .memo: return !memo.isEmpty
        case .image: return imageId != nil
        case .url: return !url.isEmpty
        }
    }

    private static let order: [Kind] = [.memo, .image, .url]

    private func label(_ kind: Kind) -> String {
        switch kind {
        case .memo: return "メモ"
        case .image: return "画像"
        case .url: return "URL"
        }
    }

    var body: some View {
        Group {
            // チップの行は、全部開いていても残す(状態の受け取りと、画像の選択・表示を、この 1 か所で持つため)
            Section {
                HStack(spacing: 8) {
                    ForEach(Self.order.filter { !openKinds.contains($0) }, id: \.self) { kind in
                        Button { open(kind) } label: {
                            Text("+ " + label(kind))
                                .font(.app(14, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Theme.accent.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.borderless)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: openKinds.count < Self.order.count ? 34 : 1)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: openKinds.count < Self.order.count ? 4 : 0, leading: 2,
                                          bottom: openKinds.count < Self.order.count ? 4 : 0, trailing: 0))
                .onChange(of: outsideTap) { _, _ in closeEmptyAfterTap() }
                .onChange(of: photoItem) { _, item in
                    guard let item else { return }
                    Task { await loadPhoto(item) }
                }
                .photosPicker(isPresented: $showPicker, selection: $photoItem, matching: .images)
                .fullScreenCover(isPresented: $showViewer) {
                    if let id = imageId { AttachmentImageViewer(imageId: id) }
                }
            }
            if openKinds.contains(.memo) {
                Section {
                    TextField("メモ(任意)", text: $memo, axis: .vertical).lineLimit(2...5)
                        .focused($focus, equals: .memo)
                } header: { Text("メモ").textCase(nil) }
            }
            if openKinds.contains(.image) { imageSection }
            if openKinds.contains(.url) { urlSection }
        }
    }

    // MARK: 画像

    private var imageSection: some View {
        Section {
            if let id = imageId {
                thumbnail(id)
            } else {
                Button {
                    touch(.image)
                    showPicker = true
                } label: {
                    Label("画像を選ぶ", systemImage: "photo")
                        .font(.app(15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .buttonStyle(.borderless)
            }
        } header: {
            HStack {
                Text("画像").textCase(nil)
                Spacer()
                if imageId != nil {
                    pencil(editing: imageEditing, label: "画像") { imageEditing.toggle() }
                }
            }
        }
    }

    private func thumbnail(_ id: String) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                touch(.image)
                if !imageEditing { showViewer = true }
            } label: {
                Group {
                    if let image = AttachmentStore.image(id) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        ZStack {
                            Color(.secondarySystemFill)
                            Text("この端末には\nありません").font(.app(11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("画像を開く")
            if imageEditing {
                Button {
                    touch(.image)
                    imageId = nil
                    imageEditing = false
                    withAnimation { _ = openKinds.remove(.image) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(.black.opacity(0.6), in: Circle())
                        .padding(6)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("画像を外す")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let id = AttachmentStore.save(data) else { return }
        if let old = imageId { AttachmentStore.delete(old) }
        imageId = id
        imageEditing = false
    }

    // MARK: URL

    private var urlSection: some View {
        Section {
            if has(.url), !urlEditing {
                if let dest = AttachmentLink.destination(url) {
                    Link(destination: dest) {
                        Text(url).lineLimit(1).truncationMode(.middle)
                    }
                } else {
                    Text(url).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                }
            } else {
                TextField("https://", text: $url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focus, equals: .url)
                    .onSubmit { focus = nil }
            }
        } header: {
            HStack {
                Text("URL").textCase(nil)
                Spacer()
                if has(.url), !urlEditing {
                    pencil(editing: false, label: "URL") {
                        urlEditing = true
                        focus = .url
                    }
                }
            }
        }
        // キーボードを閉じたとき、中身があれば、タップで開けるリンクにする
        .onChange(of: focus) { old, new in
            if old == .url, new != .url, has(.url) { urlEditing = false }
            if new == .url { urlEditing = true }
        }
    }

    // MARK: 共通

    private func pencil(editing: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button {
            touch(.image)
            action()
        } label: {
            Image(systemName: editing ? "checkmark" : "pencil")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(editing ? "\(label)の編集を終える" : "\(label)を編集")
    }

    private func touch(_ kind: Kind) { lastTouch = (kind, Date()) }

    private func open(_ kind: Kind) {
        closeEmpty(keeping: kind)
        withAnimation(.easeOut(duration: 0.2)) { _ = openKinds.insert(kind) }
        if kind == .url { urlEditing = true }
        switch kind {
        case .memo: focus = .memo
        case .url: focus = .url
        case .image: break
        }
    }

    /// 空で、いま入力中でもない欄を閉じる(`keeping` は閉じない)
    private func closeEmpty(keeping: Kind?) {
        for kind in openKinds where kind != keeping && !has(kind) && focus != kind {
            withAnimation(.easeOut(duration: 0.2)) { _ = openKinds.remove(kind) }
        }
    }

    /// 欄の外をタップしたとき。押した直後の欄(画像の選択ボタンなど)は閉じない。
    /// フォーカスの移り変わりが落ち着いてから、判断する
    private func closeEmptyAfterTap() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if imageEditing, let t = lastTouch, t.kind == .image, Date().timeIntervalSince(t.at) < 0.4 {
                // 画像の編集中の操作なので、そのまま
            } else if imageEditing {
                imageEditing = false
            }
            if let t = lastTouch, Date().timeIntervalSince(t.at) < 0.5 {
                closeEmpty(keeping: t.kind)
            } else {
                closeEmpty(keeping: nil)
            }
        }
    }
}

/// 予定一覧の行の右端に出す、カメラ(画像を大きく開く)とリンク(ブラウザで開く)のアイコン。画像・URL があるものだけ出す
struct AttachmentIcons: View {
    let imageId: String?
    let url: String?
    @State private var showViewer = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 0) {
            if let id = imageId {
                Button { showViewer = true } label: { icon("camera") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("画像を開く")
                    .fullScreenCover(isPresented: $showViewer) { AttachmentImageViewer(imageId: id) }
            }
            if let url, let dest = AttachmentLink.destination(url) {
                Button { openURL(dest) } label: { icon("link") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("リンクを開く")
            }
        }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17))
            .foregroundStyle(.secondary)
            .frame(width: 36, height: 40)
            .contentShape(Rectangle())
    }
}
