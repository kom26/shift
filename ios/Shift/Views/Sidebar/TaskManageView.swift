import SwiftUI

/// ドロワーの「タスク・開始・締切管理」。タスク・開始・締切の 3 つのタブで、それぞれの項目を一覧にする
struct TaskManageView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var kind: TaskKind = .due
    @State private var editing: TaskEditTarget?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabs
                content
            }
            .navigationTitle("タスク・開始・締切管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                addToolbarItem
            }
            .sheet(item: $editing) { TaskEditor(original: $0.task, isNew: $0.isNew) }
        }
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(TaskKind.allCases) { k in
                Button { withAnimation(.snappy) { kind = k } } label: {
                    HStack(spacing: 5) {
                        Text(k.title).font(.app(14, weight: kind == k ? .semibold : .regular))
                        let n = store.openTaskCount(kind: k)
                        if n > 0 {
                            Text("\(n)")
                                .font(.app(11, weight: .bold))
                                .foregroundStyle(Theme.onAccent)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(Theme.accent, in: Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(kind == k ? Color(.systemBackground) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        let rows = store.taskRows(kind: kind)
        if rows.isEmpty {
            Spacer()
            Text(kind == .plain ? "タスクはありません" : "\(kind.title)はありません")
                .foregroundStyle(Color.secondary)
            Spacer()
        } else {
            List {
                if kind == .plain {
                    ForEach(rows) { rowView($0) }
                } else {
                    ForEach(groups(rows), id: \.date) { g in
                        Section {
                            ForEach(g.rows) { rowView($0) }
                        } header: {
                            Text(Self.dateText(g.date))
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func rowView(_ row: TaskRow) -> some View {
        TaskRowView(row: row) {
            withAnimation(.snappy) { store.toggleTaskDone(id: row.task.id) }
        }
        .contentShape(Rectangle())
        .onTapGesture { editing = TaskEditTarget(task: row.task, isNew: false) }
        .accessibilityAddTraits(.isButton)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { store.deleteTask(id: row.task.id) } label: {
                swipeDeleteLabel
            }
            .tint(swipeDeleteTint)
        }
    }

    private func groups(_ rows: [TaskRow]) -> [(date: String, rows: [TaskRow])] {
        var order: [String] = []
        var map: [String: [TaskRow]] = [:]
        for r in rows {
            let d = r.date ?? ""
            if map[d] == nil { order.append(d) }
            map[d, default: []].append(r)
        }
        return order.map { (date: $0, rows: map[$0] ?? []) }
    }

    private static func dateText(_ ds: String) -> String {
        let p = Rules.ymd(ds)
        let wd = Rules.weekdayLabels(startMonday: false)[Rules.weekday(ds)]
        return "\(p.month)/\(p.day) (\(wd))"
    }

    /// カレンダー右上の ⊕ と同じ、丸いボタン。いま開いているタブの種類で、入力の画面を開く
    private var addButton: some View {
        Button {
            let today = Rules.today()
            let t: TaskItem
            switch kind {
            case .plain: t = .new()
            case .start: t = .new(startDate: today)
            case .due: t = .new(dueDate: today)
            }
            editing = TaskEditTarget(task: t, isNew: true)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 36, height: 36)
                .background(Theme.accent, in: Circle())
        }
        .accessibilityLabel("追加")
    }

    @ToolbarContentBuilder
    private var addToolbarItem: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) { addButton }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) { addButton }
        }
    }
}
