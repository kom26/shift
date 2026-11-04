import SwiftUI

/// 絞り込み。「通常予定」「職場」「予定レイヤー」の 3 つのくくりで、チェックしたものだけを表示する。
/// 職場側とレイヤー側は両方に合う予定だけが出る。何もチェックしなければ全て表示する
struct FilterSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var workplaceCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for ev in store.events {
            counts[store.workplace(for: ev)?.id ?? Store.noWorkplaceKey, default: 0] += 1
        }
        return counts
    }

    private var layerCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for ev in store.events {
            for id in ev.effectiveLayerIds { counts[id, default: 0] += 1 }
        }
        return counts
    }

    var body: some View {
        let wCounts = workplaceCounts
        let lCounts = layerCounts
        let normalCount = wCounts[Store.noWorkplaceKey] ?? 0
        NavigationStack {
            List {
                if normalCount > 0 || store.checkedWorkplaces.contains(Store.noWorkplaceKey) {
                    Section("通常予定") {
                        row(name: "通常予定すべて", color: nil, count: normalCount,
                            checked: store.checkedWorkplaces.contains(Store.noWorkplaceKey)) {
                            store.toggleWorkplaceFilter(Store.noWorkplaceKey)
                        }
                    }
                }
                if !store.workplaces.isEmpty {
                    Section("職場(\(store.workplaces.count))") {
                        ForEach(store.workplaces) { w in
                            row(name: w.name, color: w.color, count: wCounts[w.id] ?? 0,
                                checked: store.checkedWorkplaces.contains(w.id)) {
                                store.toggleWorkplaceFilter(w.id)
                            }
                        }
                    }
                }
                Section("予定レイヤー(\(store.allLayers.count))") {
                    ForEach(store.allLayers) { l in
                        row(name: l.name, color: l.color, count: lCounts[l.id] ?? 0,
                            checked: store.checkedLayers.contains(l.id)) {
                            store.toggleLayerFilter(l.id)
                        }
                    }
                }
            }
            .navigationTitle("絞り込み")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("すべて表示") { store.clearFilters() }.disabled(!store.isFiltering)
                }
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(name: String, color: String?, count: Int, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if let color {
                    ColorDot(hex: color, size: 14)
                } else {
                    Circle().strokeBorder(Color.secondary, lineWidth: 1).frame(width: 14, height: 14)
                }
                Text(name)
                Text("\(count)件").foregroundStyle(.secondary)
                Spacer()
                if checked { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
        .foregroundStyle(.primary)
    }
}
