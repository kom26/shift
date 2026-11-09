import SwiftUI

/// ドロワーの「職場の管理」。職場の追加・編集・並べ替え・削除
struct WorkplaceManageView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editingWorkplace: Workplace?
    @State private var addingWorkplace = false
    @State private var pendingDelete: Workplace?
    @State private var editMode: EditMode = .inactive

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if store.workplaces.isEmpty {
                        Text("職場が登録されていません")
                            .font(.app(13))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.workplaces) { w in
                        HStack(spacing: 10) {
                            // 消す前に、確認を出す
                            if editMode.isEditing { DeleteMinusButton { pendingDelete = w } }
                            Button { editingWorkplace = w } label: {
                                HStack(spacing: 10) {
                                    ColorDot(hex: w.color, size: 12)
                                    Text(w.name).foregroundStyle(.primary)
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .onMove { store.moveWorkplaces(from: $0, to: $1) }
                    Button("＋ 職場を追加") { addingWorkplace = true }
                } footer: {
                    Text("職場を追加すると労働時間や給与管理ができます。")
                }
            }
            .navigationTitle("職場の管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { EditButton() }
            }
            .confirmationDialog("この職場を削除しますか?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible, presenting: pendingDelete) { w in
                Button("削除", role: .destructive) { store.deleteWorkplace(id: w.id) }
            } message: { w in
                Text("\(store.workplaceEventCount(w.id))件の予定は「指定なし」の通常予定に変更されます。")
            }
            .environment(\.editMode, $editMode)
            .sheet(item: $editingWorkplace) { WorkplaceEditor(workplace: $0) }
            .sheet(isPresented: $addingWorkplace) { WorkplaceEditor(workplace: nil) }
        }
    }
}
