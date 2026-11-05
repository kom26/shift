import SwiftUI

/// ドロワーの「職場の管理」。職場の追加・編集・並べ替え・削除
struct WorkplaceManageView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editingWorkplace: Workplace?
    @State private var addingWorkplace = false

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
                        Button { editingWorkplace = w } label: {
                            HStack(spacing: 10) {
                                ColorDot(hex: w.color, size: 12)
                                Text(w.name).foregroundStyle(.primary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { store.workplaces[$0].id }
                        ids.forEach { store.deleteWorkplace(id: $0) }
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
                ToolbarItem(placement: .cancellationAction) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
            }
            .sheet(item: $editingWorkplace) { WorkplaceEditor(workplace: $0) }
            .sheet(isPresented: $addingWorkplace) { WorkplaceEditor(workplace: nil) }
        }
    }
}
