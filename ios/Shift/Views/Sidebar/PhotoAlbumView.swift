import SwiftUI

/// そのカレンダーの予定に付いている写真の一覧。縦長 3:4 のマスを 3 列に、新しい順・月ごとに並べ、マスに日付と予定名を重ねる。
/// 自分のカレンダーでは、右上で職場・ラベル・開始締切ごとに絞り込める。共有カレンダーでは、その中で作った予定の写真だけ
struct PhotoAlbumView: View {
    /// true: 開いている共有カレンダーの写真 / false: 自分のカレンダーの写真
    let shared: Bool
    /// 「予定を見る」。その日の予定一覧を開く(一覧は閉じてから)
    var onShowDay: (String) -> Void = { _ in }

    @Environment(Store.self) private var store
    @Environment(SharedViewState.self) private var sharedView
    @Environment(\.dismiss) private var dismiss
    @State private var filter: AlbumFilter = .all
    @State private var viewing: ViewerTarget?

    private struct ViewerTarget: Identifiable {
        let id: String
    }

    private var allPhotos: [AlbumPhoto] {
        shared ? PhotoAlbum.shared(Array(sharedView.items.values)) : PhotoAlbum.own(store: store)
    }

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        let all = allPhotos
        let photos = PhotoAlbum.filtered(all, by: shared ? .all : filter)
        NavigationStack {
            ScrollView {
                if photos.isEmpty {
                    emptyView(filtered: !all.isEmpty)
                        .padding(.top, 120)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(PhotoAlbum.sections(photos)) { section in
                            Text(section.title)
                                .font(.app(15, weight: .bold))
                                .padding(.horizontal, 14)
                                .padding(.top, 14)
                                .padding(.bottom, 8)
                            LazyVGrid(columns: Self.columns, spacing: 2) {
                                ForEach(section.photos) { p in
                                    Button { viewing = ViewerTarget(id: p.id) } label: { cell(p) }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(accessibilityText(p))
                                }
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("写真").font(.app(17, weight: .semibold))
                        Text(subtitle(count: photos.count)).font(.app(11)).foregroundStyle(.secondary)
                    }
                }
                if !shared {
                    ToolbarItem(placement: .topBarTrailing) { filterMenu(all) }
                }
            }
            .fullScreenCover(item: $viewing) { target in
                PhotoViewer(photos: photos, startId: target.id, onShowDay: { date in
                    viewing = nil
                    dismiss()
                    onShowDay(date)
                })
            }
        }
    }

    // MARK: マス

    private func cell(_ p: AlbumPhoto) -> some View {
        Color(.secondarySystemFill)
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay { AttachmentImageView(imageId: p.imageId, fill: true) }
            .overlay(alignment: .top) {
                LinearGradient(colors: [.black.opacity(0.42), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 44)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.42)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 40)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                Text(p.date.map(PhotoAlbum.shortDate) ?? "日付未定")
                    .font(.app(12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.leading, 7)
                    .padding(.top, 6)
            }
            .overlay(alignment: .bottomLeading) {
                Text(p.title.isEmpty ? "(予定名なし)" : p.title)
                    .font(.app(11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.bottom, 6)
            }
            .clipped()
            .contentShape(Rectangle())
    }

    private func accessibilityText(_ p: AlbumPhoto) -> String {
        (p.date.map(PhotoAlbum.longDate) ?? "日付未定") + " " + p.title + "の写真"
    }

    private func subtitle(count: Int) -> String {
        let name = shared ? (sharedView.calendar?.name ?? "") : "自分のカレンダー"
        return name + " · \(count)枚"
    }

    @ViewBuilder
    private func emptyView(filtered: Bool) -> some View {
        if filtered {
            ContentUnavailableView("この絞り込みの写真はありません", systemImage: "photo.on.rectangle.angled",
                                   description: Text("右上の絞り込みを「すべて」に戻すと、ほかの写真が出ます"))
        } else {
            ContentUnavailableView("まだ写真がありません", systemImage: "photo.on.rectangle.angled",
                                   description: Text("予定に写真を付けると、ここに並びます"))
        }
    }

    // MARK: 絞り込み

    /// 写真のある職場・ラベルと、開始・締切だけを選べるようにする
    private func filterMenu(_ all: [AlbumPhoto]) -> some View {
        let workplaceIds = Set(all.compactMap(\.workplaceId))
        let labelKeys = Set(all.compactMap(\.labelKey))
        let workplaces = store.workplaces.filter { workplaceIds.contains($0.id) }
        let labels = store.labels.filter { labelKeys.contains($0.id) }
        let hasNoLabel = labelKeys.contains(Store.noLabelKey)
        let hasTasks = all.contains { $0.source == .task }
        return Menu {
            Picker("絞り込み", selection: $filter) {
                Text("すべて").tag(AlbumFilter.all)
                if !workplaces.isEmpty {
                    Section("勤務予定") {
                        ForEach(workplaces) { w in Text(w.name).tag(AlbumFilter.workplace(w.id)) }
                    }
                }
                if !labels.isEmpty || hasNoLabel {
                    Section("通常予定") {
                        ForEach(labels) { l in Text(l.name).tag(AlbumFilter.label(l.id)) }
                        if hasNoLabel { Text("ラベルなし").tag(AlbumFilter.label(Store.noLabelKey)) }
                    }
                }
                if hasTasks {
                    Section {
                        Text("開始・締切").tag(AlbumFilter.tasks)
                    }
                }
            }
        } label: {
            Image(systemName: filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .font(.app(20))
                .foregroundStyle(filter == .all ? Color.primary : Theme.accent)
                .frame(minWidth: 36, minHeight: 36)
        }
        .accessibilityLabel("写真の絞り込み")
    }
}

/// 写真を 1 枚ずつ大きく見る。左右にめくって前後の写真へ。「予定を見る」で、その日の予定一覧を開く
private struct PhotoViewer: View {
    let photos: [AlbumPhoto]
    let startId: String
    var onShowDay: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    /// 見ている写真。開いた写真から始める(左右にスワイプで、前後の写真へ)
    @State private var current: String

    init(photos: [AlbumPhoto], startId: String, onShowDay: @escaping (String) -> Void) {
        self.photos = photos
        self.startId = startId
        self.onShowDay = onShowDay
        _current = State(initialValue: startId)
    }

    private var index: Int { photos.firstIndex { $0.id == current } ?? 0 }

    var body: some View {
        let p = photos.indices.contains(index) ? photos[index] : nil
        VStack(spacing: 0) {
            HStack {
                Button("閉じる") { dismiss() }
                    .font(.app(16))
                    .frame(width: 72, alignment: .leading)
                Spacer(minLength: 4)
                Text(p?.date.map(PhotoAlbum.longDate) ?? "日付未定")
                    .font(.app(15, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(index + 1) / \(photos.count)")
                    .font(.app(12))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 72, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            TabView(selection: $current) {
                ForEach(photos) { photo in
                    AttachmentImageView(imageId: photo.imageId)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.map { $0.title.isEmpty ? "(予定名なし)" : $0.title } ?? "")
                        .font(.app(16, weight: .bold))
                        .lineLimit(1)
                    Text(p?.source == .task ? "開始・締切" : "予定")
                        .font(.app(12))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 4)
                if let date = p?.date {
                    Button { onShowDay(date) } label: {
                        Text("予定を見る")
                            .font(.app(13, weight: .bold))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(.white.opacity(0.18), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .foregroundStyle(.white)
        .background(Color.black.ignoresSafeArea())
    }
}
