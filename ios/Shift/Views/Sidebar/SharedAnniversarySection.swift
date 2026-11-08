import SwiftUI

/// 共有カレンダーの設定の「誕生日・記念日」。押すと一覧が開き、右上の + から追加する
/// (自分のカレンダーの設定の「記念日・誕生日」と同じ作り)
struct SharedAnniversarySection: View {
    let calendar: SharedCalendar
    let canWrite: Bool
    /// 参加者の名前(uid から引ける)
    let names: [String: String]
    let myUid: String?
    /// 相手に見える自分の名前(自分の誕生日の名前に使う)
    let displayName: String

    var body: some View {
        Section {
            NavigationLink {
                SharedAnniversaryListView(calendar: calendar, canWrite: canWrite, names: names, myUid: myUid,
                                          displayName: displayName)
            } label: {
                Text("誕生日・記念日")
            }
        }
    }
}

/// 共有カレンダーの誕生日・記念日の一覧。右上の + を押すと、新規作成か、自分の誕生日を追加かを選べる(開いている間は × になる)。
/// 自分の誕生日を追加したものは、アカウントの誕生日と連動し、ここからはアイコンと色だけ変えられる
struct SharedAnniversaryListView: View {
    @Environment(SharedViewState.self) private var sharedView
    @Environment(Store.self) private var store
    let calendar: SharedCalendar
    let canWrite: Bool
    let names: [String: String]
    let myUid: String?
    let displayName: String

    @State private var items: [SharedAnniversary] = []
    @State private var menuOpen = false
    @State private var editing: AnniversaryEditTarget?
    @State private var message: String?

    var body: some View {
        List {
            if items.isEmpty {
                Text("登録されていません").foregroundStyle(.secondary)
            }
            ForEach(items.sorted { ($0.month, $0.day) < ($1.month, $1.day) }) { item in
                row(item)
            }
        }
        .navigationTitle("誕生日・記念日")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canWrite {
                ToolbarItem(placement: .primaryAction) { plusButton }
            }
        }
        .task { await reload() }
        .sheet(item: $editing) { target in
            AnniversaryEditor(
                item: target.item,
                onCommit: { a in
                    Task {
                        let owner = items.first(where: { $0.id == a.id })?.ownerUid
                        if !(await sharedView.saveAnniversary(a, in: calendar.id, ownerUid: owner)) { message = "保存できませんでした" }
                        await reload()
                    }
                },
                onRemove: target.item.flatMap { old -> (() -> Void)? in
                    // 連動した誕生日は、本人しか消せない
                    if let s = items.first(where: { $0.id == old.id }), s.linked, s.ownerUid != myUid { return nil }
                    return { Task { await sharedView.removeAnniversary(id: old.id, in: calendar.id); await reload() } }
                })
        }
        .alert("お知らせ", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    /// 開いている間は 45° 傾いて × になる + ボタン
    private var plusButton: some View {
        Button {
            // アカウントに誕生日がなければ、選ばずに新規作成へ
            if store.myBirthday == nil { newOne() } else { menuOpen.toggle() }
        } label: {
            Image(systemName: "plus")
                .rotationEffect(.degrees(menuOpen ? 45 : 0))
                .animation(.snappy, value: menuOpen)
        }
        .accessibilityLabel(menuOpen ? "閉じる" : "追加")
        .popover(isPresented: $menuOpen, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Button { newOne() } label: {
                    Label("新規作成", systemImage: "plus.circle").frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }
                Divider()
                Button { addMine() } label: {
                    Label("自分の誕生日を追加", systemImage: "gift").frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }
            }
            .buttonStyle(.plain)
            .font(.app(16))
            .frame(width: 230)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func row(_ item: SharedAnniversary) -> some View {
        let a = item.anniversary
        let mine = item.ownerUid == myUid
        return Button {
            if canWrite { editing = AnniversaryEditTarget(item: a) }
        } label: {
            HStack(spacing: 10) {
                AnniversaryIcon(icon: a.icon, color: a.color, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.name.isEmpty ? "(名前なし)" : a.name).foregroundStyle(Color.primary)
                    Text(a.dateText + " ・ " + (mine ? "あなた" : (names[item.ownerUid] ?? "")))
                        .font(.app(12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if item.linked {
                    Image(systemName: "link").font(.app(12)).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            if canWrite && !(item.linked && !mine) {
                Button(role: .destructive) {
                    Task { await sharedView.removeAnniversary(id: item.id, in: calendar.id); await reload() }
                } label: {
                    Label("削除", systemImage: "trash").labelStyle(SwipeDeleteLabelStyle())
                }
            }
        }
    }

    private func newOne() {
        menuOpen = false
        // ポップオーバーが閉じきってから、編集画面を開く
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { editing = AnniversaryEditTarget(item: nil) }
    }

    private func addMine() {
        menuOpen = false
        guard let mine = store.myBirthday else {
            message = "先に、アカウントの「名前とアバター」で、誕生日を登録してください。"
            return
        }
        guard let uid = myUid, !items.contains(where: { $0.id == SharedAnniversary.linkedId(uid: uid) }) else {
            message = "自分の誕生日は、もう追加されています。"
            return
        }
        Task {
            if !(await sharedView.addMyBirthday(mine, name: displayName, in: calendar.id)) { message = "追加できませんでした" }
            await reload()
        }
    }

    private func reload() async {
        if let list = await sharedView.anniversaries(in: calendar.id) { items = list }
    }
}

struct AnniversaryEditTarget: Identifiable {
    let id = UUID()
    let item: Anniversary?
}
