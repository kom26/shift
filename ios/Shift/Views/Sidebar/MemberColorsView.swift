import SwiftUI

/// 共有カレンダーの「参加者ごとの色」。予定バーの色を、この端末のこの共有カレンダーでだけ変える。
/// 色は、予定を開いて変える「予定の色・表示」と同じ設定(どちらで変えても、両方に反映する)
struct MemberColorsView: View {
    @Environment(SharedViewState.self) private var shared
    let calendar: SharedCalendar
    let members: [CalendarMember]
    let myUid: String?

    /// 自分を先頭に、参加している人
    private var people: [CalendarMember] {
        let active = members.filter { $0.status == .active }
        return active.filter { $0.id == myUid } + active.filter { $0.id != myUid }
    }

    private func name(_ m: CalendarMember) -> String {
        let n = m.displayName.isEmpty ? "(名前なし)" : m.displayName
        return m.id == myUid ? n + "(自分)" : n
    }

    var body: some View {
        List {
            if shared.calendar?.id != calendar.id {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            } else {
                Section("参加者") {
                    ForEach(people) { m in
                        NavigationLink {
                            MemberColorDetail(title: m.displayName.isEmpty ? "(名前なし)" : m.displayName, ownerUid: m.id,
                                              isMe: m.id == myUid)
                        } label: {
                            HStack(spacing: 12) {
                                UserAvatar(uid: m.id, name: m.displayName, avatar: m.avatar, size: 30)
                                Text(name(m))
                                Spacer()
                                dots(shared.colorGroups(ownerUid: m.id))
                            }
                        }
                    }
                }
                Section {
                    NavigationLink {
                        MemberColorDetail(title: calendar.name, ownerUid: nil)
                    } label: {
                        HStack(spacing: 12) {
                            CalendarIconView(icon: calendar.icon.isEmpty ? CalendarIcon.defaultName : calendar.icon, size: 30)
                            Text(calendar.name)
                            Spacer()
                            dots(shared.colorGroups(ownerUid: nil))
                        }
                    }
                } header: {
                    Text("このカレンダーで作った予定")
                } footer: {
                    Text("予定バーの色を、この共有カレンダーのあなたの画面でだけ変えます。最初は、予定を作った人の色です。")
                }
            }
        }
        .navigationTitle("参加者ごとの色")
        .navigationBarTitleDisplayMode(.inline)
        // 予定の色は、開いている共有カレンダーの予定から作る。開いていなければ開く(背景を選ぶときと同じ)
        .task { if shared.calendar?.id != calendar.id { await shared.open(calendar) } }
    }

    private func dots(_ groups: [SharedColorGroup]) -> some View {
        HStack(spacing: 4) {
            ForEach(groups.prefix(5)) { g in ColorDot(hex: shared.color(for: g.sample), size: 14) }
        }
    }
}

/// 参加者 1 人(または、このカレンダーで作った予定)の色。まとめて変えるか、予定の種類ごとに変える。
/// 相手の職場名・ラベル名は出さない(「種類 1」と、その種類の予定のバーで見分ける)
struct MemberColorDetail: View {
    @Environment(SharedViewState.self) private var shared
    @Environment(Store.self) private var store
    let title: String
    /// nil は、共有カレンダーの中で作った予定
    let ownerUid: String?
    /// 自分の予定(共有カレンダーの上での見た目だけ変わる。自分のカレンダーの色は変わらない)
    var isMe = false
    /// まとめて変える色(開いたときは、種類 1 の今の色)。「この色にまとめる」を押すまで、変えない
    @State private var bulk = ""
    @State private var editing: SharedEvent?

    private var groups: [SharedColorGroup] { shared.colorGroups(ownerUid: ownerUid) }

    var body: some View {
        Form {
            if groups.isEmpty {
                Section { Text("共有されている予定はありません。").foregroundStyle(.secondary) }
            } else {
                Section {
                    ColorRow(color: $bulk, recent: store.customColors, onDeleteRecent: { store.removeCustomColor($0) })
                    Button("この色にまとめる") {
                        store.rememberColor(bulk)
                        shared.setColor(bulk, for: groups)
                    }
                    .disabled(bulk.isEmpty || groups.allSatisfy { shared.color(for: $0.sample) == bulk })
                } header: {
                    Text("まとめて変える")
                } footer: {
                    Text(ownerUid == nil ? "このカレンダーで作った予定を、すべてこの色にします。"
                         : isMe ? "あなたの予定を、この共有カレンダーの上でだけ、すべてこの色にします。自分のカレンダーの色は変わりません。"
                         : "\(title)さんの予定を、すべてこの色にします。")
                }
                Section {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { i, g in
                        Button { editing = g.sample } label: { groupRow(g, number: i + 1) }
                            .foregroundStyle(.primary)
                    }
                } header: {
                    Text(isMe ? "職場・ラベルごと" : "予定の種類ごと")
                }
                Section {
                    Button("作成者の色に戻す") {
                        shared.setColor(nil, for: groups)
                        if let first = groups.first { bulk = shared.color(for: first.sample) }
                    }
                    .disabled(!groups.contains { shared.color(for: $0.sample) != $0.sample.color })
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if bulk.isEmpty { bulk = groups.first.map { shared.color(for: $0.sample) } ?? "" } }
        .sheet(item: $editing) { SharedColorSheet(event: $0) }
    }

    private func groupRow(_ g: SharedColorGroup, number: Int) -> some View {
        let shown = g.sample.shiftEvent(color: shared.color(for: g.sample), showsTime: shared.showsTime(for: g.sample))
        return HStack(spacing: 12) {
            EventBar(span: BarSpan(event: shown, col: 0, span: 1, isStart: true, isEnd: true), height: 18, fontSize: 10)
                .frame(width: 96, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                // 自分の予定は職場・ラベルの名前。ほかの人の予定は、名前を出さずに「種類 1」
                Text(isMe ? (g.sample.name.isEmpty ? "指定なし" : g.sample.name) : "種類 \(number)").font(.app(15))
                Text(verbatim: "\(g.count)件の予定").font(.app(12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            ColorDot(hex: shared.color(for: g.sample), size: 14)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
