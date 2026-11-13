import SwiftUI

/// 共有カレンダーの「参加者ごとの色」。予定バーの色を、この端末のこの共有カレンダーでだけ変える。
/// 色は、予定を開いて変える「予定の色・表示」と同じ設定(どちらで変えても、両方に反映する)
struct MemberColorsView: View {
    @Environment(SharedViewState.self) private var shared
    let calendar: SharedCalendar
    let members: [CalendarMember]
    let myUid: String?

    private var others: [CalendarMember] {
        members.filter { $0.id != myUid && $0.status == .active }
    }

    var body: some View {
        List {
            if shared.calendar?.id != calendar.id {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            } else {
                Section("参加者") {
                    ForEach(others) { m in
                        NavigationLink {
                            MemberColorDetail(title: m.displayName.isEmpty ? "(名前なし)" : m.displayName, ownerUid: m.id)
                        } label: {
                            HStack(spacing: 12) {
                                UserAvatar(uid: m.id, name: m.displayName, avatar: m.avatar, size: 30)
                                Text(m.displayName.isEmpty ? "(名前なし)" : m.displayName)
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
    /// まとめて変える色(開いたときは、種類 1 の今の色)
    @State private var bulk = ""
    @State private var editing: SharedEvent?
    /// こちらで bulk を入れ直したとき(戻したとき)は、まとめて変えない
    @State private var ignoreNext = false

    private var groups: [SharedColorGroup] { shared.colorGroups(ownerUid: ownerUid) }

    var body: some View {
        Form {
            if groups.isEmpty {
                Section { Text("共有されている予定はありません。").foregroundStyle(.secondary) }
            } else {
                Section {
                    ColorRow(color: $bulk, recent: store.customColors, onDeleteRecent: { store.removeCustomColor($0) })
                } header: {
                    Text("まとめて変える")
                } footer: {
                    Text(ownerUid == nil ? "このカレンダーで作った予定を、すべてこの色にします。" : "\(title)さんの予定を、すべてこの色にします。")
                }
                Section {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { i, g in
                        Button { editing = g.sample } label: { groupRow(g, number: i + 1) }
                            .foregroundStyle(.primary)
                    }
                } header: {
                    Text("予定の種類ごと")
                } footer: {
                    Text("押すと、予定を開いたときと同じ「予定の色・表示」が開きます。相手が登録している職場やラベルの名前は出しません。")
                }
                Section {
                    Button("作成者の色に戻す") {
                        shared.setColor(nil, for: groups)
                        if let first = groups.first.map({ shared.color(for: $0.sample) }), first != bulk {
                            ignoreNext = true
                            bulk = first
                        }
                    }
                    .disabled(!groups.contains { shared.color(for: $0.sample) != $0.sample.color })
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if bulk.isEmpty { bulk = groups.first.map { shared.color(for: $0.sample) } ?? "" } }
        .onChange(of: bulk) { old, new in
            // 開いたときに入れた色では、変えない(選んだときだけ、まとめて変える)
            if ignoreNext { ignoreNext = false; return }
            guard !old.isEmpty, !new.isEmpty else { return }
            store.rememberColor(new)
            shared.setColor(new, for: groups)
        }
        .sheet(item: $editing) { SharedColorSheet(event: $0) }
    }

    private func groupRow(_ g: SharedColorGroup, number: Int) -> some View {
        let shown = g.sample.shiftEvent(color: shared.color(for: g.sample), showsTime: shared.showsTime(for: g.sample))
        return HStack(spacing: 12) {
            EventBar(span: BarSpan(event: shown, col: 0, span: 1, isStart: true, isEnd: true), height: 18, fontSize: 10)
                .frame(width: 96, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text("種類 \(number)").font(.app(15))
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
