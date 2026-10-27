import SwiftUI

struct FilterSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    private struct Row: Identifiable {
        let id: String
        let name: String
        let color: String?
        let count: Int
    }

    private var rows: [Row] {
        var counts: [String: Int] = [:]
        for ev in store.events {
            counts[store.workplace(for: ev)?.id ?? Store.noWorkplaceKey, default: 0] += 1
        }
        var list = store.workplaces.map {
            Row(id: $0.id, name: $0.name, color: $0.color, count: counts[$0.id] ?? 0)
        }
        if let n = counts[Store.noWorkplaceKey], n > 0 {
            list.append(Row(id: Store.noWorkplaceKey, name: "通常予定", color: nil, count: n))
        }
        return list
    }

    var body: some View {
        NavigationStack {
            List {
                if rows.isEmpty {
                    Text("職場がありません").foregroundStyle(.secondary)
                }
                ForEach(rows) { r in
                    Button { store.toggleWorkplaceFilter(r.id) } label: {
                        HStack {
                            if let c = r.color {
                                ColorDot(hex: c, size: 14)
                            } else {
                                Circle().strokeBorder(Color.secondary, lineWidth: 1).frame(width: 14, height: 14)
                            }
                            Text(r.name)
                            Text("\(r.count)件").foregroundStyle(.secondary)
                            Spacer()
                            if store.checkedWorkplaces.contains(r.id) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("絞り込み")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("すべて表示") { store.clearWorkplaceFilter() }.disabled(store.checkedWorkplaces.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}
