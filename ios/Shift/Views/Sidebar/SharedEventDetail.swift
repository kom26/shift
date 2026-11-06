import SwiftUI

struct SharedDetailTarget: Identifiable {
    let id = UUID()
    let eventId: String
}

/// 参加者のアバター。名前の頭文字を、持ち主ごとに決まった色の丸に入れる
struct UserAvatar: View {
    let uid: String
    let name: String
    /// 空なら名前の頭文字。`img:` で始まれば写真(AvatarPhoto)。以前に選んだ絵文字も、そのまま表示する
    var avatar: String = ""
    var size: CGFloat = 28

    private static let palette = ["#6a8cf0", "#e0707a", "#4fae8a", "#d9993d", "#a36ad9", "#4aa3c7", "#c9688f", "#7d8a3a"]

    /// 頭文字の背景を自分で選んだとき、avatar は「bg:#rrggbb」になる
    static let backgroundPrefix = "bg:"

    /// 頭文字の背景に選べる色(最初の自動は、持ち主ごとに決まる色)
    static let backgroundChoices = palette + ["#8e8e93", "#3a3a3c"]

    static func customBackground(_ avatar: String) -> String? {
        avatar.hasPrefix(backgroundPrefix) ? String(avatar.dropFirst(backgroundPrefix.count)) : nil
    }

    /// uid から色を決める(同じ人はいつも同じ色)。端末や起動ごとに変わらない計算にする
    static func color(for uid: String) -> String {
        let sum = uid.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[sum % palette.count]
    }

    static func initial(of name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0) } ?? "?"
    }

    var body: some View {
        Group {
            if let photo = AvatarPhoto.image(from: avatar) {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                let custom = Self.customBackground(avatar)
                let showsInitial = avatar.isEmpty || custom != nil
                Text(showsInitial ? Self.initial(of: name) : avatar)
                    .font(.system(size: size * (showsInitial ? 0.46 : 0.58), weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Color(hex: custom ?? Self.color(for: uid))))
            }
        }
        .accessibilityLabel(name.isEmpty ? "参加者" : name)
    }
}

/// 写真のアバター。正方形に中央でクロップして小さくし、文字列(`img:` + base64 の JPEG)にして
/// 絵文字と同じ avatar 欄に入れる。数 KB なので、別の保存場所はいらない
enum AvatarPhoto {
    static let prefix = "img:"
    /// 取り込む一辺(px)。表示は最大 56pt なので 3 倍でも足りる
    static let side: CGFloat = 168

    private static let cache = NSCache<NSString, UIImage>()

    static func isPhoto(_ avatar: String) -> Bool { avatar.hasPrefix(prefix) }

    static func image(from avatar: String) -> UIImage? {
        guard isPhoto(avatar) else { return nil }
        let key = avatar as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let data = Data(base64Encoded: String(avatar.dropFirst(prefix.count))),
              let img = UIImage(data: data) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }

    /// 範囲を合わせて切り取った正方形の画像から、avatar 文字列を作る
    static func encode(square: UIImage) -> String? {
        guard let jpeg = square.jpegData(compressionQuality: 0.75) else { return nil }
        return prefix + jpeg.base64EncodedString()
    }

    /// 写真のデータから avatar 文字列を作る。正方形でなければ、中央を正方形に切り取る
    static func encode(_ data: Data) -> String? {
        guard let src = UIImage(data: data), src.size.width > 0, src.size.height > 0 else { return nil }
        let shortSide = min(src.size.width, src.size.height)
        let scale = side / shortSide
        let drawn = CGSize(width: src.size.width * scale, height: src.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let square = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            src.draw(in: CGRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2,
                                width: drawn.width, height: drawn.height))
        }
        guard let jpeg = square.jpegData(compressionQuality: 0.75) else { return nil }
        return prefix + jpeg.base64EncodedString()
    }
}

/// 共有カレンダーの予定の詳細。予定者のアバター、タイトル、時間と、「職場・ラベルカラー」だけ。
/// 色は、この端末の共有カレンダー上だけで変えられる(自分の予定でも、相手の予定でも)
struct SharedEventDetail: View {
    @Environment(SharedViewState.self) private var shared
    @Environment(\.dismiss) private var dismiss
    let eventId: String
    @State private var pickingColor = false
    @State private var editing: SharedEditTarget?

    var body: some View {
        NavigationStack {
            Group {
                if let e = shared.event(eventId) {
                    content(e)
                } else {
                    // 消された予定
                    Text("この予定は削除されました").foregroundStyle(.secondary)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                if shared.isEditable(eventId), let e = shared.event(eventId) {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("編集") { editing = SharedEditTarget(event: e, isNew: false) }
                    }
                }
            }
            .sheet(item: $editing, onDismiss: { if shared.event(eventId) == nil { dismiss() } }) {
                SharedEventEditor(target: $0)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(.systemBackground))
    }

    private func content(_ e: SharedEvent) -> some View {
        let owner = shared.owner(of: eventId)
        return List {
            VStack(spacing: 10) {
                if !e.isCalendarOwned, let owner {
                    UserAvatar(uid: owner.uid, name: owner.name, avatar: owner.avatar, size: 56)
                    if !owner.name.isEmpty { Text(owner.name).font(.app(13)).foregroundStyle(.secondary) }
                } else {
                    Image(systemName: "person.2.fill").font(.title).foregroundStyle(.secondary)
                }
                Text(e.title.isEmpty ? "(タイトルなし)" : e.title)
                    .font(.app(24, weight: .bold))
                    .multilineTextAlignment(.center)
                timeRow(e)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowSeparator(.hidden)

            Button { pickingColor = true } label: {
                HStack(spacing: 8) {
                    Text("予定の色・表示")
                    Spacer()
                    ColorDot(hex: shared.color(for: e), size: 16)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)
        }
        .listStyle(.plain)
        .sheet(isPresented: $pickingColor) { SharedColorSheet(event: e) }
    }

    private static func dateText(_ ds: String) -> String {
        let p = Rules.ymd(ds)
        let wd = Rules.weekdayLabels(startMonday: false)[Rules.weekday(ds)]
        return "\(p.year)年\(p.month)月\(p.day)日(\(wd))"
    }

    @ViewBuilder
    private func timeRow(_ e: SharedEvent) -> some View {
        if e.allDay {
            VStack(spacing: 2) {
                Text(e.startDate == e.endDate ? Self.dateText(e.startDate)
                     : "\(Self.dateText(e.startDate)) 〜 \(Self.dateText(e.endDate))")
                    .font(.app(15, weight: .semibold))
                Text("終日").font(.app(13)).foregroundStyle(.secondary)
            }
        } else {
            HStack(alignment: .center, spacing: 14) {
                VStack(spacing: 2) {
                    Text(Self.dateText(e.startDate)).font(.app(12)).foregroundStyle(.secondary)
                    Text(e.startTime ?? "").font(.app(30, weight: .bold).monospacedDigit())
                }
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                VStack(spacing: 2) {
                    Text(Self.dateText(e.endDate)).font(.app(12)).foregroundStyle(.secondary)
                    Text(e.endTime ?? "").font(.app(30).monospacedDigit())
                }
            }
        }
    }
}

/// 共有カレンダー上だけの、職場・ラベルの色の変更
struct SharedColorSheet: View {
    @Environment(SharedViewState.self) private var shared
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let event: SharedEvent
    @State private var color: String
    /// nil は、共有した人の表示に合わせる
    @State private var showsTime: Bool?

    init(event: SharedEvent) {
        self.event = event
        _color = State(initialValue: event.color)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ColorRow(color: $color, recent: store.customColors, onDeleteRecent: { store.removeCustomColor($0) })
                } footer: {
                    Text("同じ職場・ラベルの予定は、すべて同じ色に変わります。変わるのは、この共有カレンダーのあなたの画面上だけです。ほかの人の画面や、元の予定の色は変わりません。")
                }
                Section {
                    Picker("カレンダー上の表記", selection: $showsTime) {
                        Text("共有者に合わせる").tag(Bool?.none)
                        Text("予定名").tag(Bool?.some(false))
                        Text("時間").tag(Bool?.some(true))
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("バーの表示")
                } footer: {
                    Text("初期は、共有した人のカレンダーでの表示に合わせます(その人が時間を出していれば時間)。同じ職場・ラベルの予定は、すべて同じ表示に変わります。時間のない予定(終日など)は、予定名のままです。")
                }
                Section {
                    Button("元の色に戻す") {
                        shared.setColor(nil, for: event)
                        dismiss()
                    }
                    .disabled(shared.color(for: event) == event.color)
                }
            }
            .navigationTitle("予定の色・表示")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.rememberColor(color)
                        shared.setColor(color == event.color ? nil : color, for: event)
                        shared.setShowsTime(showsTime, for: event)
                        dismiss()
                    }
                }
            }
            .onAppear {
                color = shared.color(for: event)
                showsTime = shared.showsTime(for: event)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(.systemGroupedBackground))
    }
}
