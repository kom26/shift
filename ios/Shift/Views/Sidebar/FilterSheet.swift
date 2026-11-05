import SwiftUI

/// 絞り込み。「勤務予定」(職場ごと)と「通常予定」(ラベルごと)の 2 つのくくり。
/// くくりをタップすると中身がまとめて選ばれ、中身を 1 つずつ選ぶこともできる。何も選ばなければ全て表示する
struct FilterSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Mark { case off, partial, on }

    private func mark(selected: Int, of total: Int) -> Mark {
        selected == 0 ? .off : (selected >= total ? .on : .partial)
    }

    private var workCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for ev in store.events { if let w = store.workplace(for: ev) { counts[w.id, default: 0] += 1 } }
        return counts
    }

    private var labelCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for ev in store.events where store.workplace(for: ev) == nil {
            counts[ev.labelId ?? Store.noLabelKey, default: 0] += 1
        }
        return counts
    }

    var body: some View {
        let wCounts = workCounts
        let lCounts = labelCounts
        let labelKeys = store.labels.map(\.id) + [Store.noLabelKey]
        NavigationStack {
            List {
                if !store.workplaces.isEmpty {
                    Section {
                        groupRow("勤務予定",
                                 mark: mark(selected: store.checkedWorkplaces.count, of: store.workplaces.count)) {
                            store.setWorkplaceGroup(store.checkedWorkplaces.count < store.workplaces.count)
                        }
                        ForEach(store.workplaces) { w in
                            childRow(name: w.name, color: w.color, count: wCounts[w.id] ?? 0,
                                     checked: store.checkedWorkplaces.contains(w.id)) {
                                store.toggleWorkplaceFilter(w.id)
                            }
                        }
                    }
                }
                Section {
                    groupRow("通常予定",
                             mark: mark(selected: store.checkedLabels.count, of: labelKeys.count)) {
                        store.setLabelGroup(store.checkedLabels.count < labelKeys.count)
                    }
                    ForEach(store.labels) { l in
                        childRow(name: l.name, color: l.color, count: lCounts[l.id] ?? 0,
                                 checked: store.checkedLabels.contains(l.id)) {
                            store.toggleLabelFilter(l.id)
                        }
                    }
                    childRow(name: "ラベルなし", color: EventLabel.noneColor, count: lCounts[Store.noLabelKey] ?? 0,
                             checked: store.checkedLabels.contains(Store.noLabelKey)) {
                        store.toggleLabelFilter(Store.noLabelKey)
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

    private func box(_ mark: Mark) -> some View {
        Image(systemName: mark == .on ? "checkmark.square.fill" : mark == .partial ? "minus.square.fill" : "square")
            .foregroundStyle(mark == .off ? Color.secondary : Theme.accent)
            .font(.title3)
    }

    private func groupRow(_ title: String, mark: Mark, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                box(mark)
                Text(title).font(.app(16, weight: .semibold))
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
    }

    private func childRow(name: String, color: String, count: Int, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                box(checked ? .on : .off)
                ColorDot(hex: color, size: 14)
                Text(name)
                Text("\(count)件").foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.leading, 20)
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
    }
}
