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

    /// 共有カレンダーの画像の名前の頭。"cal~<カレンダーID>~<画像ID>" で、クラウドの保存先が決まる
    static let calendarPrefix = "cal~"

    static func calendarImageId(calendarId: String) -> String { "\(calendarPrefix)\(calendarId)~\(UUID().uuidString)" }

    /// 共有カレンダーの画像なら、そのカレンダーの ID
    static func calendarId(of imageId: String) -> String? {
        guard imageId.hasPrefix(calendarPrefix) else { return nil }
        let parts = imageId.split(separator: "~", omittingEmptySubsequences: false)
        return parts.count == 3 ? String(parts[1]) : nil
    }

    /// 保存する画像の大きさの目安(300KB 前後)。元の写真は残さない
    static let targetBytes = 300_000

    /// 300KB 前後になるまで、画質と大きさを下げた JPEG にする。長い辺は、最初は 1600px まで。
    /// 画質を 0.75 から 0.4 まで下げても収まらなければ、大きさを 8 割にして、やり直す(これ以上は縮めない下限は、長い辺 400px)
    static func shrink(_ image: UIImage, maxBytes: Int = targetBytes) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        var side = min(longest, 1600)
        var best: Data?
        while true {
            let scale = side / longest
            let size = CGSize(width: max(1, (image.size.width * scale).rounded()), height: max(1, (image.size.height * scale).rounded()))
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            for quality in stride(from: 0.75, through: 0.4, by: -0.05) {
                let jpeg = renderer.jpegData(withCompressionQuality: quality) { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                best = jpeg
                if jpeg.count <= maxBytes { return jpeg }
            }
            if side <= 400 { return best }
            side = max(400, (side * 0.8).rounded())
        }
    }

    /// 300KB 前後に縮めて保存し、名前を返す。calendarId を渡すと、共有カレンダーの画像として保存する
    static func save(_ data: Data, calendarId: String? = nil) -> String? {
        guard let image = UIImage(data: data), let jpeg = shrink(image) else { return nil }
        let id = calendarId.map { calendarImageId(calendarId: $0) } ?? UUID().uuidString
        do {
            try jpeg.write(to: fileURL(id), options: .atomic)
            return id
        } catch {
            return nil
        }
    }

    static func image(_ id: String) -> UIImage? { UIImage(contentsOfFile: fileURL(id).path) }

    static func data(_ id: String) -> Data? { try? Data(contentsOf: fileURL(id)) }

    static func exists(_ id: String) -> Bool { FileManager.default.fileExists(atPath: fileURL(id).path) }

    /// クラウドから取ってきた画像を、端末に置く
    static func write(_ data: Data, id: String) { try? data.write(to: fileURL(id), options: .atomic) }

    static func delete(_ id: String) { try? FileManager.default.removeItem(at: fileURL(id)) }

    /// 端末にある画像の名前と、置いた日時(片づけに使う)
    static func localFiles() -> [(id: String, created: Date)] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return urls.compactMap { url in
            guard url.pathExtension == "jpg" else { return nil }
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            return (url.deletingPathExtension().lastPathComponent, created)
        }
    }
}

/// 編集画面の間だけ、画像の追加と取り外しを覚えておく。保存したときに、外した画像を消し、
/// キャンセルしたときは、その間に足した画像を消す(キャンセルで、元の画像が消えないように)
final class AttachmentSession {
    private(set) var added: [String] = []
    private var removed: [String] = []
    private var committed = false

    func didAdd(_ id: String) { added.append(id) }

    func didRemove(_ id: String) {
        if let i = added.firstIndex(of: id) {
            // この編集で足したものは、すぐ消してよい
            added.remove(at: i)
            Task { await AttachmentCloud.remove(id) }
        } else {
            removed.append(id)
        }
    }

    /// 保存した。外した画像を消す(`keeping` は、いま付いている画像)
    func commit(keeping: String?) {
        committed = true
        for id in removed where id != keeping { Task { await AttachmentCloud.remove(id) } }
        removed = []
    }

    /// 画面を閉じた。保存していなければ、足した画像を消す
    func discardIfUncommitted() {
        guard !committed else { return }
        for id in added { Task { await AttachmentCloud.remove(id) } }
        added = []
    }
}

/// 画像 1 枚の表示。端末になければ、クラウドから取ってくる
struct AttachmentImageView: View {
    let imageId: String
    var fill = false
    @State private var image: UIImage?
    @State private var loading = false

    var body: some View {
        Group {
            if let image {
                if fill { Image(uiImage: image).resizable().scaledToFill() } else { Image(uiImage: image).resizable().scaledToFit() }
            } else {
                ZStack {
                    Color(.secondarySystemFill)
                    if loading {
                        ProgressView()
                    } else {
                        Text("画像を読み込めません").font(.app(11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
            }
        }
        .task(id: imageId) {
            image = AttachmentStore.image(imageId)
            guard image == nil else { return }
            loading = true
            if await AttachmentCloud.download(imageId) { image = AttachmentStore.image(imageId) }
            loading = false
        }
    }
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
            AttachmentImageView(imageId: imageId)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    /// 画像の追加と取り外しを覚えておく(保存・キャンセルで、あとから片づける)
    var session: AttachmentSession
    /// 共有カレンダーの予定を直すときの、そのカレンダーの ID(画像を、共有カレンダーの保存先に置く)
    var calendarId: String?

    private enum Kind: Hashable { case memo, image, url }

    @State private var openKinds: Set<Kind> = []
    /// 削除の確認待ちの欄(画像・URL)
    @State private var pendingRemove: Kind?
    @State private var urlEditing = false
    @State private var showViewer = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showPicker = false
    @State private var lastTouch: (kind: Kind, at: Date)?
    @FocusState private var focus: Kind?
    @Environment(\.openURL) private var openURL

    init(memo: Binding<String>, url: Binding<String>, imageId: Binding<String?>, outsideTap: Int, session: AttachmentSession,
         calendarId: String? = nil) {
        self.session = session
        self.calendarId = calendarId
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
                // キーボードが閉じたとき、空のメモ・URL の欄は閉じる
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                    closeEmptyAfterTap()
                }
                .onChange(of: photoItem) { _, item in
                    guard let item else { return }
                    Task { await loadPhoto(item) }
                }
                .alert(pendingRemove.map { "\(label($0))を削除しますか?" } ?? "",
                       isPresented: Binding(get: { pendingRemove != nil }, set: { if !$0 { pendingRemove = nil } })) {
                    Button("キャンセル", role: .cancel) {}
                    Button("削除", role: .destructive) {
                        if let kind = pendingRemove { removeConfirmed(kind) }
                    }
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
                        // この欄の中のタップは、「欄の外をタップした」には数えない
                        .simultaneousGesture(TapGesture().onEnded { touch(.memo) })
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
                if imageId != nil { removeButton(.image) }
            }
        }
    }

    private func thumbnail(_ id: String) -> some View {
        Button {
            touch(.image)
            showViewer = true
        } label: {
            AttachmentImageView(imageId: id, fill: true)
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("画像を開く")
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let id = AttachmentStore.save(data, calendarId: calendarId) else { return }
        if let old = imageId { session.didRemove(old) }
        session.didAdd(id)
        imageId = id
        Task { await AttachmentCloud.upload(id) }
    }

    // MARK: URL

    private var urlSection: some View {
        Section {
            if has(.url), !urlEditing {
                if let dest = AttachmentLink.destination(url) {
                    Button { openURL(dest) } label: {
                        Text(url).lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("リンクを開く")
                } else {
                    Text(url).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    TextField("https://", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focus, equals: .url)
                        .simultaneousGesture(TapGesture().onEnded { touch(.url) })
                        .onSubmit { focus = nil }
                    // 入れた URL を、まとめて消す
                    if !url.isEmpty {
                        Button {
                            touch(.url)
                            url = ""
                            focus = .url
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.secondary.opacity(0.7))
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("URLを消す")
                    }
                }
            }
        } header: {
            HStack {
                Text("URL").textCase(nil)
                Spacer()
                if has(.url), !urlEditing { removeButton(.url) }
            }
        }
        // キーボードを閉じたとき、中身があれば、タップで開けるリンクにする
        .onChange(of: focus) { old, new in
            if old == .url, new != .url, has(.url) { urlEditing = false }
            if new == .url { urlEditing = true }
        }
    }

    // MARK: 共通

    /// 見出しの右端の ×。押すと、確認(画面の真ん中のダイアログ)を出して、削除すれば、欄ごと消す
    private func removeButton(_ kind: Kind) -> some View {
        Button {
            touch(kind)
            pendingRemove = kind
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.secondary.opacity(0.7))
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(label(kind))を削除")
    }

    private func removeConfirmed(_ kind: Kind) {
        switch kind {
        case .image:
            if let old = imageId { session.didRemove(old) }
            imageId = nil
        case .url:
            url = ""
            urlEditing = true
        case .memo:
            memo = ""
        }
        withAnimation(.easeOut(duration: 0.2)) { _ = openKinds.remove(kind) }
    }

    private func touch(_ kind: Kind) { lastTouch = (kind, Date()) }

    private func open(_ kind: Kind) {
        // チップを押したタップは、フォームの「欄の外をタップした」にも数えられるので、いま開く欄を、押した欄として覚えておく
        touch(kind)
        closeEmpty(keeping: kind)
        withAnimation(.easeOut(duration: 0.2)) { _ = openKinds.insert(kind) }
        if kind == .url { urlEditing = true }
        switch kind {
        case .memo: focus = .memo
        case .url: focus = .url
        case .image: break
        }
    }

    /// 空の欄を閉じる(`keeping` は閉じない)。入力中(キーボードが出ている)の空の欄も閉じて、入力を終える。
    /// 文字を打っていなくても「入力中」のままになって、ほかのチップを押しても閉じない、ということがないように
    private func closeEmpty(keeping: Kind?) {
        for kind in openKinds where kind != keeping && !has(kind) {
            if focus == kind { focus = nil }
            withAnimation(.easeOut(duration: 0.2)) { _ = openKinds.remove(kind) }
        }
    }

    /// 欄の外をタップしたとき。押した直後の欄(画像の選択ボタンなど)は閉じない。
    /// フォーカスの移り変わりが落ち着いてから、判断する
    private func closeEmptyAfterTap() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
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
