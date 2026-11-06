import SwiftUI

/// 共有カレンダーの設定の「誕生日・記念日」。+ を押すと、新規作成か、自分の誕生日を追加かを選べる(開いている間は × になる)。
/// 自分の誕生日を追加したものは、アカウントの誕生日と連動し、ここからはアイコンと色だけ変えられる
struct SharedAnniversarySection: View {
    @Environment(SharedViewState.self) private var sharedView
    @Environment(Store.self) private var store
    let calendar: SharedCalendar
    let canWrite: Bool
    /// 参加者の名前(uid から引ける)
    let names: [String: String]
    let myUid: String?

    @State private var items: [SharedAnniversary] = []
    @State private var menuOpen = false
    @State private var editing: AnniversaryEditTarget?
    @State private var message: String?

    var body: some View {
        Section {
            if menuOpen {
                Button { newOne() } label: { Label("新規作成", systemImage: "plus.circle") }
                Button { addMine() } label: { Label("自分の誕生日を追加", systemImage: "gift") }
            }
            ForEach(items.sorted { ($0.month, $0.day) < ($1.month, $1.day) }) { item in
                row(item)
            }
            if items.isEmpty && !menuOpen {
                Text("まだありません").foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("誕生日・記念日")
                Spacer()
                if canWrite { plusButton }
            }
        } footer: {
            Text("「自分の誕生日を追加」は、アカウントの誕生日が入ります。ここからは変えられず(アイコンと色だけ変えられます)、アカウント設定を変えるとここも変わります。")
        }
        .task { await reload() }
        .animation(.snappy, value: menuOpen)
        .sheet(item: $editing) { target in
            AnniversaryEditor(
                item: target.item,
                onCommit: { a in
                    Task {
                        if !(await sharedView.saveAnniversary(a, in: calendar.id)) { message = "保存できませんでした" }
                        await reload()
                    }
                },
                onRemove: target.item.map { old in
                    { Task { await sharedView.removeAnniversary(id: old.id, in: calendar.id); await reload() } }
                })
        }
        .alert("お知らせ", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    /// 開いている間は 45° 傾いて × になる丸いボタン
    private var plusButton: some View {
        Button { menuOpen.toggle() } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 28, height: 28)
                .background(Theme.accent, in: Circle())
                .rotationEffect(.degrees(menuOpen ? 45 : 0))
        }
        .buttonStyle(.borderless)
        .textCase(nil)
        .accessibilityLabel(menuOpen ? "閉じる" : "誕生日・記念日を追加")
    }

    private func row(_ item: SharedAnniversary) -> some View {
        let a = item.anniversary
        let mine = item.ownerUid == myUid
        return Button {
            if mine { editing = AnniversaryEditTarget(item: a) }
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
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            if mine || calendar.ownerUid == myUid {
                Button("削除", role: .destructive) {
                    Task { await sharedView.removeAnniversary(id: item.id, in: calendar.id); await reload() }
                }
            }
        }
    }

    private func newOne() {
        menuOpen = false
        editing = AnniversaryEditTarget(item: nil)
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
            if !(await sharedView.addMyBirthday(mine, in: calendar.id)) { message = "追加できませんでした" }
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
