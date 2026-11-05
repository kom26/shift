import SwiftUI

struct SharedDetailTarget: Identifiable {
    let id = UUID()
    let eventId: String
}

/// 参加者のアバター。名前の頭文字を、持ち主ごとに決まった色の丸に入れる
struct UserAvatar: View {
    let uid: String
    let name: String
    var size: CGFloat = 28

    private static let palette = ["#6a8cf0", "#e0707a", "#4fae8a", "#d9993d", "#a36ad9", "#4aa3c7", "#c9688f", "#7d8a3a"]

    /// uid から色を決める(同じ人はいつも同じ色)。端末や起動ごとに変わらない計算にする
    static func color(for uid: String) -> String {
        let sum = uid.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[sum % palette.count]
    }

    static func initial(of name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0) } ?? "?"
    }

    var body: some View {
        Text(Self.initial(of: name))
            .font(.system(size: size * 0.46, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(hex: Self.color(for: uid))))
            .accessibilityLabel(name.isEmpty ? "参加者" : name)
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
    }

    private func content(_ e: SharedEvent) -> some View {
        let owner = shared.owner(of: eventId)
        return List {
            VStack(spacing: 10) {
                if !e.isCalendarOwned, let owner {
                    UserAvatar(uid: owner.uid, name: owner.name, size: 56)
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
                    Text("職場・ラベルカラー")
                    Spacer()
                    ColorDot(hex: shared.color(for: e), size: 16)
                    Text(groupName(e)).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)
        }
        .listStyle(.plain)
        .sheet(isPresented: $pickingColor) { SharedColorSheet(event: e) }
    }

    private func groupName(_ e: SharedEvent) -> String {
        if e.isCalendarOwned { return "共有カレンダー" }
        return e.name.isEmpty ? "指定なし" : e.name
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

    init(event: SharedEvent) {
        self.event = event
        _color = State(initialValue: event.color)
    }

    private var groupName: String {
        event.isCalendarOwned ? "共有カレンダーの予定" : (event.name.isEmpty ? "指定なし" : event.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ColorRow(color: $color, recent: store.customColors, onDeleteRecent: { store.removeCustomColor($0) })
                } footer: {
                    Text("「\(groupName)」の予定の色を、この共有カレンダーの中だけで変えます。ほかの人の画面や、元の予定の色は変わりません。")
                }
                Section {
                    Button("元の色に戻す") {
                        shared.setColor(nil, for: event)
                        dismiss()
                    }
                    .disabled(shared.color(for: event) == event.color)
                }
            }
            .navigationTitle("\(groupName)の色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.rememberColor(color)
                        shared.setColor(color == event.color ? nil : color, for: event)
                        dismiss()
                    }
                }
            }
            .onAppear { color = shared.color(for: event) }
        }
        .presentationDetents([.medium, .large])
    }
}
