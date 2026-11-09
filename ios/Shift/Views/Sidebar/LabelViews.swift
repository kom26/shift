import SwiftUI

struct LabelTarget: Identifiable {
    let id = UUID()
    let label: EventLabel
    let isNew: Bool
}

extension Store {
    /// 新しいラベルの初期値(色は、グレーを除いて使っていないものから順に)
    func newLabelDraft() -> EventLabel {
        let colors = Store.defaultColors.dropFirst()
        return EventLabel(id: "", name: "", color: colors[colors.startIndex + labels.count % colors.count])
    }
}

/// 予定の編集画面の「職場・ラベル」から開く、下から出る選択シート。
/// 職場を選ぶと勤務予定、ラベル(または指定なし)を選ぶと通常予定になる。
/// 右上の「編集」を押すと、行のタップが名前・色の編集になり、右端に並べ替えが出る。「指定なし」は固定で、直せない
struct WorkLabelSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// 最初は上まで広げて開く(あとから、半分に下げられる)
    @State private var detent: PresentationDetent = .large

    let workplaceId: String?
    let labelId: String?
    let onSelect: (_ workplaceId: String?, _ labelId: String?) -> Void

    private enum Adding: Identifiable {
        case workplace, label
        var id: Int { self == .workplace ? 0 : 1 }
    }

    @State private var editing = false
    @State private var adding: Adding?
    @State private var workplaceCountBeforeAdd = 0
    @State private var labelCountBeforeAdd = 0
    @State private var editingWorkplace: Workplace?
    @State private var editingLabel: LabelTarget?
    /// 削除の確認待ち(スワイプや、編集中の赤い − から)
    @State private var pendingWorkplace: Workplace?
    @State private var pendingLabel: EventLabel?

    var body: some View {
        NavigationStack {
            List {
                Section("職場") {
                    ForEach(store.workplaces) { w in
                        row(name: w.name, color: w.color, selected: workplaceId == w.id) {
                            if editing { editingWorkplace = w } else { choose(workplace: w.id) }
                        }
                    }
                    .onMove { store.moveWorkplaces(from: $0, to: $1) }
                    .onDelete { offsets in
                        if let i = offsets.first { pendingWorkplace = store.workplaces[i] }
                    }
                    if !editing {
                        Button {
                            workplaceCountBeforeAdd = store.workplaces.count
                            adding = .workplace
                        } label: {
                            Label("職場を追加", systemImage: "plus")
                        }
                        if store.workplaces.isEmpty {
                            Text("職場を追加すると労働時間や給与管理ができます。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("ラベル") {
                    row(name: "指定なし", color: EventLabel.noneColor, selected: workplaceId == nil && labelId == nil) {
                        if !editing { choose(label: nil) }
                    }
                    .moveDisabled(true)
                    ForEach(store.labels) { l in
                        row(name: l.name, color: l.color, selected: workplaceId == nil && labelId == l.id) {
                            if editing { editingLabel = LabelTarget(label: l, isNew: false) } else { choose(label: l.id) }
                        }
                    }
                    .onMove { store.moveLabels(from: $0, to: $1) }
                    .onDelete { offsets in
                        if let i = offsets.first { pendingLabel = store.labels[i] }
                    }
                    if !editing {
                        Button {
                            labelCountBeforeAdd = store.labels.count
                            adding = .label
                        } label: {
                            Label("ラベルを追加", systemImage: "plus")
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(editing ? .active : .inactive))
            .navigationTitle(editing ? "職場・ラベルを編集" : "職場・ラベル")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing ? "完了" : "編集") { withAnimation { editing.toggle() } }
                        .disabled(!editing && store.workplaces.isEmpty && store.labels.isEmpty)
                }
            }
            .confirmationDialog("この職場を削除しますか?", isPresented: Binding(get: { pendingWorkplace != nil }, set: { if !$0 { pendingWorkplace = nil } }),
                                titleVisibility: .visible, presenting: pendingWorkplace) { w in
                Button("削除", role: .destructive) { remove(workplace: w) }
            } message: { w in
                Text("「\(w.name)」を削除します。この職場の予定は消えません。職場の指定だけがなくなります。")
            }
            .confirmationDialog("このラベルを削除しますか?", isPresented: Binding(get: { pendingLabel != nil }, set: { if !$0 { pendingLabel = nil } }),
                                titleVisibility: .visible, presenting: pendingLabel) { l in
                Button("削除", role: .destructive) { remove(label: l) }
            } message: { l in
                Text("削除すると、\(store.labelEventCount(l.id))件の予定は「指定なし」に戻ります。予定は消えません。")
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationBackground(Color(.systemGroupedBackground))
        .sheet(item: $adding, onDismiss: selectAdded) { kind in
            switch kind {
            case .workplace: WorkplaceEditor(workplace: nil)
            case .label: LabelEditor(label: store.newLabelDraft(), isNew: true)
            }
        }
        .sheet(item: $editingWorkplace) { WorkplaceEditor(workplace: $0) }
        .sheet(item: $editingLabel) { LabelEditor(label: $0.label, isNew: $0.isNew) }
    }

    private func row(name: String, color: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ColorDot(hex: color, size: 14)
                Text(name)
                Spacer()
                if !editing {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(selected ? Color.primary : Color.secondary.opacity(0.5))
                }
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
    }

    /// 選んでいた職場を消したときは、「指定なし」に切り替える
    private func remove(workplace w: Workplace) {
        let wasSelected = workplaceId == w.id
        store.deleteWorkplace(id: w.id)
        if wasSelected { onSelect(nil, nil) }
    }

    private func remove(label l: EventLabel) {
        let wasSelected = workplaceId == nil && labelId == l.id
        store.deleteLabel(id: l.id)
        if wasSelected { onSelect(nil, nil) }
    }

    private func choose(workplace id: String) {
        onSelect(id, nil)
        dismiss()
    }

    private func choose(label id: String?) {
        onSelect(nil, id)
        dismiss()
    }

    /// 追加したものは、そのまま選んでシートを閉じる
    private func selectAdded() {
        if store.workplaces.count > workplaceCountBeforeAdd, let w = store.workplaces.last {
            workplaceCountBeforeAdd = store.workplaces.count
            choose(workplace: w.id)
        } else if store.labels.count > labelCountBeforeAdd, let l = store.labels.last {
            labelCountBeforeAdd = store.labels.count
            choose(label: l.id)
        }
    }
}

/// ラベルの管理(ドロワーから)。並べ替え・名前と色の編集・追加・削除
struct LabelManageView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var target: LabelTarget?
    @State private var pendingDelete: EventLabel?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        ColorDot(hex: EventLabel.noneColor, size: 14)
                        Text("指定なし")
                        Spacer()
                        Text("\(store.labelEventCount(nil))件").foregroundStyle(.secondary)
                    }
                    .moveDisabled(true)
                    ForEach(store.labels) { l in
                        Button { target = LabelTarget(label: l, isNew: false) } label: {
                            HStack(spacing: 12) {
                                ColorDot(hex: l.color, size: 14)
                                Text(l.name)
                                Spacer()
                                Text("\(store.labelEventCount(l.id))件").foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in
                        // 削除したラベルの予定は「指定なし」に戻る(予定は消えない)。消す前に、確認を出す
                        if let i = offsets.first { pendingDelete = store.labels[i] }
                    }
                    .onMove { store.moveLabels(from: $0, to: $1) }
                }
                Section {
                    Button { target = LabelTarget(label: store.newLabelDraft(), isNew: true) } label: {
                        Label("ラベルを追加", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("ラベルの管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { EditButton() }
            }
            .sheet(item: $target) { LabelEditor(label: $0.label, isNew: $0.isNew) }
            .confirmationDialog("このラベルを削除しますか?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible, presenting: pendingDelete) { l in
                Button("削除", role: .destructive) { store.deleteLabel(id: l.id) }
            } message: { l in
                Text("削除すると、\(store.labelEventCount(l.id))件の予定は「指定なし」に戻ります。予定は消えません。")
            }
        }
    }
}

struct LabelEditor: View {
    let label: EventLabel
    let isNew: Bool
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var color: String
    @State private var confirmDelete = false

    init(label: EventLabel, isNew: Bool) {
        self.label = label
        self.isNew = isNew
        _name = State(initialValue: label.name)
        _color = State(initialValue: label.color)
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ラベル名(必須)", text: $name)
                    ColorRow(color: $color, recent: store.customColors, onDeleteRecent: { store.removeCustomColor($0) })
                }
                if !isNew {
                    Section {
                        Button("このラベルを削除", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("削除すると、\(store.labelEventCount(label.id))件の予定は「指定なし」に戻ります。予定は消えません。")
                    }
                }
            }
            .navigationTitle(isNew ? "ラベルを追加" : "ラベルを編集")
            .keyboardDismissBar()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "追加" : "保存") { save() }.disabled(!canSave)
                }
            }
            .confirmationDialog("このラベルを削除しますか?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    store.deleteLabel(id: label.id)
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(.systemGroupedBackground))
    }

    private func save() {
        store.rememberColor(color)
        if isNew {
            store.addLabel(name: name, color: color)
        } else {
            store.updateLabel(id: label.id, name: name, color: color)
        }
        dismiss()
    }
}
