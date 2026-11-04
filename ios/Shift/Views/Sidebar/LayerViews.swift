import SwiftUI

struct LayerTarget: Identifiable {
    let id = UUID()
    let layer: Layer
    let isNew: Bool
}

extension Store {
    /// 新しいレイヤーの初期値(色は、使っていないものから順に)
    func newLayerDraft() -> Layer {
        Layer(id: "", name: "", color: Store.defaultColors[layers.count % Store.defaultColors.count])
    }
}

/// レイヤーの一覧と追加・編集
struct LayerListView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editing: LayerTarget?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(Layer.mine, editable: false)
                    ForEach(store.layers) { l in row(l, editable: true) }
                } footer: {
                    Text("予定は複数のレイヤーに入れられます。通常予定は、必ずどれか 1 つのレイヤーに入ります。")
                }
                Section {
                    Button {
                        editing = LayerTarget(layer: store.newLayerDraft(), isNew: true)
                    } label: {
                        Label("レイヤーを追加", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("レイヤーの管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
            }
            .sheet(item: $editing) { LayerEditor(layer: $0.layer, isNew: $0.isNew) }
        }
    }

    private func row(_ l: Layer, editable: Bool) -> some View {
        Button {
            if editable { editing = LayerTarget(layer: l, isNew: false) }
        } label: {
            HStack {
                ColorDot(hex: l.color, size: 14)
                Text(l.name)
                Text("\(store.layerEventCount(l.id))件").foregroundStyle(.secondary)
                Spacer()
                if editable { Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary) }
            }
        }
        .foregroundStyle(.primary)
    }
}

struct LayerEditor: View {
    let layer: Layer
    let isNew: Bool
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var color: String
    @State private var confirmDelete = false

    init(layer: Layer, isNew: Bool) {
        self.layer = layer
        self.isNew = isNew
        _name = State(initialValue: layer.name)
        _color = State(initialValue: layer.color)
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("レイヤー名(必須)", text: $name)
                    ColorRow(color: $color, recent: store.customColors, onDeleteRecent: { store.removeCustomColor($0) })
                }
                if !isNew {
                    Section {
                        Button("削除", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("このレイヤーの予定は消えません。ほかにレイヤーが無い予定は「自分の予定」に戻ります。")
                    }
                }
            }
            .navigationTitle(isNew ? "レイヤーを追加" : "レイヤーを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "追加" : "保存") { save() }.disabled(!canSave)
                }
            }
            .confirmationDialog("このレイヤーを削除しますか?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    store.deleteLayer(id: layer.id)
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        store.rememberColor(color)
        if isNew {
            store.addLayer(name: name, color: color)
        } else {
            store.updateLayer(id: layer.id, name: name, color: color)
        }
        dismiss()
    }
}
