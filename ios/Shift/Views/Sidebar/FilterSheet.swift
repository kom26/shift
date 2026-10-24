import SwiftUI

struct FilterSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if store.colorsInUse.isEmpty {
                    Text("予定がありません").foregroundStyle(.secondary)
                }
                ForEach(store.colorsInUse, id: \.self) { c in
                    Button { store.toggleColor(c) } label: {
                        HStack {
                            Circle().fill(Color(hex: c)).frame(width: 14, height: 14)
                            Text("\(store.events.filter { $0.color == c }.count)件")
                            Spacer()
                            if store.checkedColors.contains(c) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("色で絞り込み")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("すべて表示") { store.clearColors() }.disabled(store.checkedColors.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}
