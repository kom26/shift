import SwiftUI

/// ☰ドロワー。月集計(色フィルタ)と全予定リスト、下部の操作ボタン
struct DrawerSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let anchor: String
    let onEdit: (ShiftEvent) -> Void
    let onAddUnplaced: () -> Void
    let onBulkImport: () -> Void
    let onSettings: () -> Void

    @State private var panelOpen = false

    private var monthLabel: String {
        let p = Rules.ymd(anchor)
        return String(format: "%04d/%02d", p.year, p.month)
    }

    /// 配置済みは開始日の昇順(同日は元の順)、そのあとに未配置(元の順)
    private var allEvents: [ShiftEvent] {
        let placed = store.events.enumerated()
            .filter { $0.element.placed && $0.element.startDate != nil }
            .sorted { a, b in
                let da = a.element.startDate ?? ""
                let db = b.element.startDate ?? ""
                return da != db ? da < db : a.offset < b.offset
            }
            .map { $0.element }
        let rest = store.events.filter { !($0.placed && $0.startDate != nil) }
        return placed + rest
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DisclosureGroup(isExpanded: $panelOpen) {
                        let rows = store.monthPanel(of: anchor)
                        if rows.isEmpty {
                            Text("データなし").font(.footnote).foregroundStyle(.secondary)
                        } else {
                            ForEach(rows) { panelRow($0) }
                        }
                        Button("すべて表示") { store.clearColors() }
                            .disabled(store.checkedColors.isEmpty)
                    } label: {
                        Text("月集計 \(monthLabel)").font(.subheadline.weight(.semibold))
                    }
                }
                Section("予定") {
                    let items = allEvents
                    if items.isEmpty {
                        Text("予定はありません").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ForEach(items) { ev in
                            eventRow(ev)
                        }
                    }
                }
                Section {
                    Button { onAddUnplaced() } label: { Label("予定を追加", systemImage: "plus") }
                    Button { onBulkImport() } label: { Label("一括取り込み", systemImage: "square.and.arrow.down") }
                    Button { onSettings() } label: { Label("設定", systemImage: "gearshape") }
                }
            }
            .navigationTitle("予定リスト")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
            }
        }
    }

    private func panelRow(_ r: PanelRow) -> some View {
        let checked = store.checkedColors.contains(r.color)
        return Button { store.toggleColor(r.color) } label: {
            HStack(spacing: 8) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(checked ? Theme.accent : Color.secondary)
                Circle().fill(Color(hex: r.color)).frame(width: 10, height: 10)
                Text(r.title.isEmpty ? "(無題)" : r.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("配置済 \(Rules.formatHours(r.placed))")
                    Text("未配置 \(Rules.formatHours(r.unplaced))")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func dateLabel(_ ev: ShiftEvent) -> String? {
        guard ev.placed, let s = ev.startDate else { return nil }
        func md(_ d: String) -> String {
            let p = Rules.ymd(d)
            return String(format: "%02d/%02d", p.month, p.day)
        }
        if let e = ev.endDate, e != s { return "\(md(s)) → \(md(e))" }
        return md(s)
    }

    private func eventRow(_ ev: ShiftEvent) -> some View {
        let time = Rules.timeLabel(ev)
        return Button {
            onEdit(ev)
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: ev.color))
                    .frame(width: 4, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ev.title.isEmpty ? "(無題)" : ev.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(dateLabel(ev) ?? "未配置")
                        if !time.isEmpty { Text(time) }
                        if let w = ev.workHours { Text("実労働 \(Rules.formatHours(w))") }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
