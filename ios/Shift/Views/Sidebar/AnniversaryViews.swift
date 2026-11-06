import SwiftUI

/// 記念日のアイコン(色つき)
struct AnniversaryIcon: View {
    let icon: Anniversary.Icon
    let color: String
    var size: CGFloat = 16

    var body: some View {
        Image(icon.asset)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(Color(hex: color))
    }
}

/// 設定 → 記念日・誕生日 の一覧(名前・日付・年齢/経過)。タップで詳細
struct AnniversaryListView: View {
    @Environment(Store.self) private var store
    @State private var adding = false

    var body: some View {
        List {
            if store.anniversaries.isEmpty {
                Text("登録されていません").foregroundStyle(.secondary)
            }
            ForEach(store.anniversaries) { a in
                NavigationLink {
                    AnniversaryDetail(id: a.id)
                } label: {
                    HStack(spacing: 10) {
                        AnniversaryIcon(icon: a.icon, color: a.color, size: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.name.isEmpty ? "(名前なし)" : a.name)
                            Text(a.dateText).font(.app(12)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if let e = a.elapsedText(asOf: Rules.today()) {
                            Text(e).font(.app(15).monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
                .deleteDisabled(a.isAccountBirthday)
            }
            .onDelete { offsets in
                // 自分の誕生日は、ここでは消せない(アカウント設定で、登録をやめる)
                let ids = offsets.map { store.anniversaries[$0] }.filter { !$0.isAccountBirthday }.map(\.id)
                ids.forEach { store.deleteAnniversary(id: $0) }
            }
        }
        .navigationTitle("記念日・誕生日")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("追加")
            }
        }
        .sheet(isPresented: $adding) { AnniversaryEditor(item: nil) }
    }
}

/// 詳細(名前・日付・経過・繰り返し・メモ)。右上の「編集」から編集画面へ。
/// カレンダーのアイコンからも開く(asOf はタップした日。年齢などをその日時点で出す)
struct AnniversaryDetail: View {
    @Environment(Store.self) private var store
    @Environment(SharedViewState.self) private var shared
    let id: String
    var asOf: String? = nil
    @State private var editing = false

    var body: some View {
        Group {
            if let a = store.anniversaries.first(where: { $0.id == id }) {
                List {
                    Section {
                        HStack(spacing: 12) {
                            AnniversaryIcon(icon: a.icon, color: a.color, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.name.isEmpty ? "(名前なし)" : a.name).font(.app(20, weight: .bold))
                                Text(a.dateText).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        if let e = a.elapsedText(asOf: asOf ?? Rules.today()) {
                            LabeledContent(a.kind == .birthday ? "年齢" : "経過", value: e)
                        }
                        LabeledContent("種類", value: a.kind == .birthday ? "誕生日" : "記念日")
                        if a.kind == .anniversary {
                            LabeledContent("くり返し", value: a.monthly ? "毎月" : "毎年")
                        }
                    }
                    if !a.memo.isEmpty {
                        Section("メモ") { Text(a.memo) }
                    }
                }
                .toolbar {
                    // 共有カレンダーの誕生日・記念日は、入れた人だけが直せる
                    if !shared.isOpen || shared.canEditAnniversary(id) {
                        ToolbarItem(placement: .primaryAction) { Button("編集") { editing = true } }
                    }
                }
                .sheet(isPresented: $editing) { editor(for: a) }
            } else {
                Text("削除されました").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("詳細")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// カレンダーのアイコンから開く詳細(閉じるボタンつき)
extension AnniversaryDetail {
    @ViewBuilder
    fileprivate func editor(for a: Anniversary) -> some View {
        if shared.isOpen, let cid = shared.calendar?.id {
            AnniversaryEditor(
                item: a,
                onCommit: { x in Task { await shared.saveAnniversary(x, in: cid) } },
                onRemove: { Task { await shared.removeAnniversary(id: a.id, in: cid) } })
        } else {
            AnniversaryEditor(item: a)
        }
    }
}

struct AnniversaryDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let id: String
    let asOf: String

    var body: some View {
        NavigationStack {
            AnniversaryDetail(id: id, asOf: asOf)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(.systemGroupedBackground))
    }
}

struct AnniversaryEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let item: Anniversary?
    /// 共有カレンダーの中では、自分の端末に保存せず、これで渡す
    var onCommit: ((Anniversary) -> Void)? = nil
    var onRemove: (() -> Void)? = nil

    @State private var a: Anniversary
    @State private var knowsYear: Bool
    @State private var yearValue: Int
    @State private var confirmDelete = false

    init(item: Anniversary?, onCommit: ((Anniversary) -> Void)? = nil, onRemove: (() -> Void)? = nil) {
        self.item = item
        self.onCommit = onCommit
        self.onRemove = onRemove
        let v = item ?? Anniversary()
        _a = State(initialValue: v)
        _knowsYear = State(initialValue: v.year != nil)
        _yearValue = State(initialValue: v.year ?? 2000)
    }

    private var thisYear: Int { Rules.ymd(Rules.today()).year }
    /// 自分の誕生日は、アイコンと色だけ変えられる(ほかは、アカウント設定から)
    private var locked: Bool { a.isAccountBirthday }

    var body: some View {
        NavigationStack {
            Form {
                if locked {
                    Section {
                        Text("自分の誕生日は、アカウント設定からのみ変更できます。ここでは、アイコンと色だけ変えられます。")
                            .font(.app(13))
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    TwoWayPicker("種類", selection: $a.kind, first: ("誕生日", Anniversary.Kind.birthday), second: ("記念日", Anniversary.Kind.anniversary))
                    TextField("名前(記念日の名前でもOK)", text: $a.name)
                }
                .disabled(locked)
                .opacity(locked ? 0.5 : 1)
                Section {
                    if a.kind == .anniversary {
                        TwoWayPicker("くり返し", selection: $a.monthly, first: ("毎年", false), second: ("毎月", true))
                    }
                    Toggle(a.kind == .birthday ? "生まれ年を入力" : "年を入力", isOn: $knowsYear)
                    if knowsYear {
                        Picker("年", selection: $yearValue) {
                            ForEach((1900...thisYear).reversed(), id: \.self) { Text("\($0)年").tag($0) }
                        }
                    }
                    Picker("月", selection: $a.month) {
                        ForEach(1...12, id: \.self) { Text("\($0)月").tag($0) }
                    }
                    Picker("日", selection: $a.day) {
                        ForEach(1...31, id: \.self) { Text("\($0)日").tag($0) }
                    }
                } footer: {
                    if a.isMonthly {
                        Text("毎月\(a.day)日に表示します。年を入れると「◯年◯ヶ月」を出します。")
                    } else if !knowsYear {
                        Text("年が分からないときは入れなくても登録できます(年齢は出ません)。")
                    }
                }
                .disabled(locked)
                .opacity(locked ? 0.5 : 1)
                Section("アイコン") {
                    HStack(spacing: 14) {
                        ForEach(Anniversary.Icon.allCases, id: \.self) { ic in
                            Button { a.icon = ic } label: {
                                AnniversaryIcon(icon: ic, color: a.color, size: 28)
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemFill)))
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .stroke(Theme.accent, lineWidth: a.icon == ic ? 2 : 0))
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(ic.label)
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Store.defaultColors, id: \.self) { c in
                                Button { a.color = c } label: {
                                    Circle().fill(Color(hex: c)).frame(width: 26, height: 26)
                                        .overlay(Circle().stroke(Theme.accent, lineWidth: a.color == c ? 3 : 0).padding(-3))
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 4)
                    }
                }
                Section("メモ") {
                    TextField("メモ(任意)", text: $a.memo, axis: .vertical).lineLimit(2...6)
                }
                .disabled(locked)
                .opacity(locked ? 0.5 : 1)
                if item != nil && !locked {
                    Section {
                        Button("削除", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(item == nil ? "記念日・誕生日を追加" : "編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        a.name = a.name.trimmingCharacters(in: .whitespaces)
                        a.year = knowsYear ? yearValue : nil
                        if a.kind == .birthday { a.monthly = false }
                        if let onCommit { onCommit(a) } else { store.saveAnniversary(a) }
                        dismiss()
                    }
                    .disabled(a.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("削除しますか?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    if let onRemove { onRemove() } else { store.deleteAnniversary(id: a.id) }
                    dismiss()
                }
            }
        }
    }
}
