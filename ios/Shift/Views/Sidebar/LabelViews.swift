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

/// 職場・ラベルの 1 行ぶん
struct ChoiceItem: Identifiable, Equatable {
    let id: String
    let name: String
    let color: String
}

/// 下から出る選択シート。タップで選ぶ。右上の「編集」を押すと、行のタップが名前・色の編集になり、右端に並べ替えが出る。
/// 職場とラベルで共通。「指定なし」「ラベルなし」は固定で、直せない
struct ChoiceSheet<AddEditor: View, ItemEditor: View>: View {
    let title: String
    let noneTitle: String
    let items: [ChoiceItem]
    let selectedId: String?
    let addTitle: String
    let onSelect: (String?) -> Void
    let onMove: (IndexSet, Int) -> Void
    @ViewBuilder let addEditor: () -> AddEditor
    @ViewBuilder let itemEditor: (String) -> ItemEditor

    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var adding = false
    @State private var countBeforeAdd = 0
    @State private var editingId: String?

    var body: some View {
        NavigationStack {
            List {
                row(id: nil, name: noneTitle, color: EventLabel.noneColor)
                ForEach(items) { item in
                    row(id: item.id, name: item.name, color: item.color)
                }
                .onMove(perform: onMove)
                if !editing {
                    Button {
                        countBeforeAdd = items.count
                        adding = true
                    } label: {
                        Label(addTitle, systemImage: "plus").foregroundStyle(Theme.accent)
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(editing ? .active : .inactive))
            .navigationTitle(editing ? "\(title)を編集" : title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing ? "完了" : "編集") { withAnimation { editing.toggle() } }
                        .disabled(!editing && items.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $adding, onDismiss: selectAdded) { addEditor() }
        .sheet(item: Binding(get: { editingId.map { IdTarget(id: $0) } }, set: { editingId = $0?.id })) {
            itemEditor($0.id)
        }
    }

    private struct IdTarget: Identifiable { let id: String }

    private func row(id: String?, name: String, color: String) -> some View {
        Button {
            if editing {
                if let id { editingId = id }
            } else {
                onSelect(id)
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                ColorDot(hex: color, size: 14)
                Text(name)
                Spacer()
                if !editing {
                    Image(systemName: selectedId == id ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(selectedId == id ? Color.primary : Color.secondary.opacity(0.5))
                }
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .moveDisabled(id == nil)
    }

    /// 追加したものは、そのまま選んでシートを閉じる
    private func selectAdded() {
        guard items.count > countBeforeAdd, let last = items.last else { return }
        onSelect(last.id)
        dismiss()
    }
}

/// ラベルの管理(ドロワーから)。並べ替え・名前と色の編集・追加・削除
struct LabelManageView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var target: LabelTarget?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        ColorDot(hex: EventLabel.noneColor, size: 14)
                        Text("ラベルなし")
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
                    .onMove { store.moveLabels(from: $0, to: $1) }
                } footer: {
                    Text("ラベルは通常予定の分類で、1 つの予定に 1 つ付けられます。勤務予定は職場でまとまるので、ラベルは付けません。職場は設定から直せます。")
                }
                Section {
                    Button { target = LabelTarget(label: store.newLabelDraft(), isNew: true) } label: {
                        Label("ラベルを追加", systemImage: "plus")
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("ラベルの管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } }
            .sheet(item: $target) { LabelEditor(label: $0.label, isNew: $0.isNew) }
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
                        Text("削除すると、\(store.labelEventCount(label.id))件の予定は「ラベルなし」に戻ります。予定は消えません。")
                    }
                }
            }
            .navigationTitle(isNew ? "ラベルを追加" : "ラベルを編集")
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

/// 予定の編集画面の「職場」から開く選択シート
struct WorkplacePickerSheet: View {
    @Environment(Store.self) private var store
    let selectedId: String?
    let onSelect: (String?) -> Void

    var body: some View {
        ChoiceSheet(title: "職場", noneTitle: "指定なし",
                    items: store.workplaces.map { ChoiceItem(id: $0.id, name: $0.name, color: $0.color) },
                    selectedId: selectedId, addTitle: "職場を追加", onSelect: onSelect,
                    onMove: { store.moveWorkplaces(from: $0, to: $1) },
                    addEditor: { WorkplaceEditor(workplace: nil) },
                    itemEditor: { id in WorkplaceEditor(workplace: store.workplaces.first { $0.id == id }) })
    }
}

/// 予定の編集画面の「ラベル」から開く選択シート
struct LabelPickerSheet: View {
    @Environment(Store.self) private var store
    let selectedId: String?
    let onSelect: (String?) -> Void

    var body: some View {
        ChoiceSheet(title: "ラベル", noneTitle: "ラベルなし",
                    items: store.labels.map { ChoiceItem(id: $0.id, name: $0.name, color: $0.color) },
                    selectedId: selectedId, addTitle: "ラベルを追加", onSelect: onSelect,
                    onMove: { store.moveLabels(from: $0, to: $1) },
                    addEditor: { LabelEditor(label: store.newLabelDraft(), isNew: true) },
                    itemEditor: { id in
                        if let l = store.label(for: id) { LabelEditor(label: l, isNew: false) }
                    })
    }
}
