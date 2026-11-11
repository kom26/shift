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

/// 編集中に行の左へ出す、赤い −。押すと、削除の確認を出す(スワイプでは削除しない)
struct DeleteMinusButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill").font(.title3).foregroundStyle(Color.red)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("削除")
    }
}

/// 予定の編集画面の「職場・ラベル」から開く、下から出る選択シート。
/// 職場を選ぶと勤務予定、ラベル(または指定なし)を選ぶと通常予定になる。
/// 右上の「編集」を押すと、行のタップが名前・色の編集になり、右端に並べ替えが出る。「指定なし」は固定で、直せない
struct WorkLabelSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// 最初は上まで広げて開く(あとから、半分に下げられる)
    @State private var detent: PresentationDetent = .large

    let workplaceId: String?
    let labelId: String?
    let onSelect: (_ workplaceId: String?, _ labelId: String?) -> Void

    private enum Adding: Identifiable {
        case workplace, label
        var id: Int { self == .workplace ? 0 : 1 }
    }

    @State private var editing = false
    @State private var adding: Adding?
    @State private var workplaceCountBeforeAdd = 0
    @State private var labelCountBeforeAdd = 0
    @State private var editingWorkplace: Workplace?
    @State private var editingLabel: LabelTarget?
    /// 削除の確認待ち(スワイプや、編集中の赤い − から)
    @State private var pendingWorkplace: Workplace?
    @State private var pendingLabel: EventLabel?

    var body: some View {
        NavigationStack {
            List {
                Section("職場") {
                    ForEach(store.workplaces) { w in
                        row(name: w.name, color: w.color, selected: workplaceId == w.id, onDelete: { pendingWorkplace = w }) {
                            if editing { editingWorkplace = w } else { choose(workplace: w.id) }
                        }
                    }
                    .onMove { store.moveWorkplaces(from: $0, to: $1) }
                    if !editing {
                        Button {
                            workplaceCountBeforeAdd = store.workplaces.count
                            adding = .workplace
                        } label: {
                            Label("職場を追加", systemImage: "plus")
                        }
                        if store.workplaces.isEmpty {
                            Text("職場を追加すると労働時間や給与管理ができます。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("ラベル") {
                    row(name: "指定なし", color: EventLabel.noneColor, selected: workplaceId == nil && labelId == nil) {
                        if !editing { choose(label: nil) }
                    }
                    .moveDisabled(true)
                    ForEach(store.labels) { l in
                        row(name: l.name, color: l.color, selected: workplaceId == nil && labelId == l.id, onDelete: { pendingLabel = l }) {
                            if editing { editingLabel = LabelTarget(label: l, isNew: false) } else { choose(label: l.id) }
                        }
                    }
                    .onMove { store.moveLabels(from: $0, to: $1) }
                    if !editing {
                        Button {
                            labelCountBeforeAdd = store.labels.count
                            adding = .label
                        } label: {
                            Label("ラベルを追加", systemImage: "plus")
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(editing ? .active : .inactive))
            .navigationTitle(editing ? "職場・ラベルを編集" : "職場・ラベル")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 何も選ばずに閉じる(編集中は、変更がその場で保存されているので、出さない)
                if !editing {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(editing ? "完了" : "編集") { withAnimation { editing.toggle() } }
                        .disabled(!editing && store.workplaces.isEmpty && store.labels.isEmpty)
                }
            }
            .alert("この職場を削除しますか?", isPresented: Binding(get: { pendingWorkplace != nil }, set: { if !$0 { pendingWorkplace = nil } }),
                                presenting: pendingWorkplace) { w in
                Button("キャンセル", role: .cancel) {}
                Button("削除", role: .destructive) { remove(workplace: w) }
            } message: { w in
                Text("\(store.workplaceEventCount(w.id))件の予定は「指定なし」の通常予定に変更されます。")
            }
            .alert("このラベルを削除しますか?", isPresented: Binding(get: { pendingLabel != nil }, set: { if !$0 { pendingLabel = nil } }),
                                presenting: pendingLabel) { l in
                Button("キャンセル", role: .cancel) {}
                Button("削除", role: .destructive) { remove(label: l) }
            } message: { l in
                Text("\(store.labelEventCount(l.id))件の予定は「指定なし」に変更されます。")
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationBackground(Color(.systemGroupedBackground))
        .sheet(item: $adding, onDismiss: selectAdded) { kind in
            switch kind {
            case .workplace: WorkplaceEditor(workplace: nil)
            case .label: LabelEditor(label: store.newLabelDraft(), isNew: true)
            }
        }
        .sheet(item: $editingWorkplace) { WorkplaceEditor(workplace: $0) }
        .sheet(item: $editingLabel) { LabelEditor(label: $0.label, isNew: $0.isNew) }
    }

    /// onDelete があるときは、編集中だけ、左に赤い − を出す
    private func row(name: String, color: String, selected: Bool, onDelete: (() -> Void)? = nil,
                     action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            if editing, let onDelete { DeleteMinusButton(action: onDelete) }
            Button(action: action) {
                HStack(spacing: 12) {
                    ColorDot(hex: color, size: 14)
                    Text(name)
                    Spacer()
                    if !editing {
                        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(selected ? Color.primary : Color.secondary.opacity(0.5))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
        }
    }

    /// 選んでいた職場を消したときは、「指定なし」に切り替える
    private func remove(workplace w: Workplace) {
        let wasSelected = workplaceId == w.id
        store.deleteWorkplace(id: w.id)
        if wasSelected { onSelect(nil, nil) }
    }

    private func remove(label l: EventLabel) {
        let wasSelected = workplaceId == nil && labelId == l.id
        store.deleteLabel(id: l.id)
        if wasSelected { onSelect(nil, nil) }
    }

    private func choose(workplace id: String) {
        onSelect(id, nil)
        dismiss()
    }

    private func choose(label id: String?) {
        onSelect(nil, id)
        dismiss()
    }

    /// 追加したものは、そのまま選んでシートを閉じる
    private func selectAdded() {
        if store.workplaces.count > workplaceCountBeforeAdd, let w = store.workplaces.last {
            workplaceCountBeforeAdd = store.workplaces.count
            choose(workplace: w.id)
        } else if store.labels.count > labelCountBeforeAdd, let l = store.labels.last {
            labelCountBeforeAdd = store.labels.count
            choose(label: l.id)
        }
    }
}

/// ラベルの管理の中で、開く先の印。labelId が nil は「指定なし」
struct LabelRoute: Hashable {
    let labelId: String?
}

/// ラベルの管理(ドロワーから)。ラベルの行をタップすると、そのラベルの予定の一覧が開く。
/// 右上の「編集」を押すと、並べ替え・追加・削除ができて、ラベル名が紫になる(タップで名前と色を直す。「指定なし」は固定)
struct LabelManageView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var target: LabelTarget?
    @State private var pendingDelete: EventLabel?
    @State private var editMode: EditMode = .inactive
    @State private var path: [LabelRoute] = []

    private var editing: Bool { editMode.isEditing }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Button { if !editing { path.append(LabelRoute(labelId: nil)) } } label: {
                        HStack(spacing: 12) {
                            ColorDot(hex: EventLabel.noneColor, size: 14)
                            Text("指定なし")
                            Spacer()
                            Text("\(store.labelEventCount(nil))件").foregroundStyle(.secondary)
                            if !editing { chevron }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.primary)
                    .moveDisabled(true)
                    ForEach(store.labels) { l in
                        HStack(spacing: 12) {
                            // 削除したラベルの予定は「指定なし」に戻る(予定は消えない)。消す前に、確認を出す
                            if editing { DeleteMinusButton { pendingDelete = l } }
                            Button {
                                if editing { target = LabelTarget(label: l, isNew: false) } else { path.append(LabelRoute(labelId: l.id)) }
                            } label: {
                                HStack(spacing: 12) {
                                    ColorDot(hex: l.color, size: 14)
                                    // 編集中は、名前が紫になって、タップで直せることを示す
                                    Text(l.name).foregroundStyle(editing ? Theme.accent : Color.primary)
                                    Spacer()
                                    Text("\(store.labelEventCount(l.id))件").foregroundStyle(.secondary)
                                    if !editing { chevron }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.primary)
                        }
                    }
                    .onMove { store.moveLabels(from: $0, to: $1) }
                }
                Section {
                    Button { target = LabelTarget(label: store.newLabelDraft(), isNew: true) } label: {
                        Label("ラベルを追加", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("ラベルの管理")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: LabelRoute.self) { LabelEventsView(labelId: $0.labelId) }
            .toolbar {
                if !editing {
                    ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(editing ? "完了" : "編集") {
                        withAnimation { editMode = editing ? .inactive : .active }
                    }
                }
            }
            .sheet(item: $target) { LabelEditor(label: $0.label, isNew: $0.isNew) }
            .environment(\.editMode, $editMode)
            .alert("このラベルを削除しますか?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                presenting: pendingDelete) { l in
                Button("キャンセル", role: .cancel) {}
                Button("削除", role: .destructive) { store.deleteLabel(id: l.id) }
            } message: { l in
                Text("\(store.labelEventCount(l.id))件の予定は「指定なし」に変更されます。")
            }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
    }
}

/// 選んだ予定の付け替え先のラベルを選ぶ、下から出るシート(いまのラベルは出さない。「指定なし」も選べる)
struct LabelMoveSheet: View {
    let currentLabelId: String?
    let onPick: (String?) -> Void
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if currentLabelId != nil { row(name: "指定なし", color: EventLabel.noneColor, id: nil) }
                ForEach(store.labels.filter { $0.id != currentLabelId }) { l in row(name: l.name, color: l.color, id: l.id) }
            }
            .navigationTitle("ラベルを変更")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(.systemGroupedBackground))
    }

    private func row(name: String, color: String, id: String?) -> some View {
        Button {
            onPick(id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ColorDot(hex: color, size: 14)
                Text(name)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
    }
}

/// ラベルの予定の一覧。日付で並べ替えられる(はじめは古い順)。「選択」で、予定を選んで、ラベルの付け替えと削除がまとめてできる
struct LabelEventsView: View {
    let labelId: String?
    @Environment(Store.self) private var store
    @State private var oldestFirst = true
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var showMove = false
    @State private var confirmDelete = false
    /// タップして、編集画面を開く予定
    @State private var editing: LabelEventEdit?

    private struct LabelEventEdit: Identifiable {
        let event: ShiftEvent
        var id: String { event.id }
    }

    private static let weekdays = ["日", "月", "火", "水", "木", "金", "土"]

    private var events: [ShiftEvent] { store.labelEvents(labelId, oldestFirst: oldestFirst) }
    private var title: String { store.label(for: labelId)?.name ?? "指定なし" }
    private var chosenCount: Int { events.filter { selected.contains($0.id) }.count }

    var body: some View {
        let list = events
        List {
            if list.isEmpty {
                Text("このラベルの予定はありません").foregroundStyle(.secondary)
            }
            ForEach(list) { e in row(e) }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    Menu {
                        Picker("並び順", selection: $oldestFirst) {
                            Text("古い順").tag(true)
                            Text("新しい順").tag(false)
                        }
                    } label: {
                        Label(oldestFirst ? "古い順" : "新しい順", systemImage: "arrow.up.arrow.down")
                    }
                    Button(selecting ? "完了" : "選択") {
                        selecting.toggle()
                        selected = []
                    }
                    .disabled(!selecting && list.isEmpty)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting { selectionBar(list) }
        }
        .sheet(item: $editing) { EventEditor(original: $0.event, isNew: false) }
        // 付け替え先は、いつもの、下から出るシートで選ぶ
        .sheet(isPresented: $showMove) {
            LabelMoveSheet(currentLabelId: labelId) { move(to: $0) }
        }
        .alert("\(chosenCount)件の予定を削除しますか?", isPresented: $confirmDelete) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                store.deleteEvents(ids: selected)
                finishSelection()
            }
        } message: {
            Text("削除した予定は元に戻せません。")
        }
    }

    private func row(_ e: ShiftEvent) -> some View {
        let on = selected.contains(e.id)
        return HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(dateText(e)).font(.app(14)).foregroundStyle(Color.primary)
                if let t = e.startTime, !e.allDay { Text(t).font(.app(12).monospacedDigit()).foregroundStyle(Color.secondary) }
            }
            .frame(width: 64, alignment: .trailing)
            RoundedRectangle(cornerRadius: 2).fill(EventColor.fill(e.color)).frame(width: 4)
            Text(e.title.isEmpty ? "(タイトルなし)" : e.title).font(.app(17)).lineLimit(1)
            Spacer(minLength: 0)
            // 選択中は、チェックを右端に出す
            if selecting {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(on ? Theme.accent : Color.secondary.opacity(0.6))
            }
        }
        .frame(height: 48)
        .contentShape(Rectangle())
        .onTapGesture {
            if selecting {
                if on { selected.remove(e.id) } else { selected.insert(e.id) }
            } else {
                editing = LabelEventEdit(event: e)
            }
        }
        .accessibilityAddTraits(.isButton)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !selecting {
                Button(role: .destructive) {
                    withAnimation { store.delete(id: e.id) }
                } label: {
                    swipeDeleteLabel
                }
                .tint(swipeDeleteTint)
            }
        }
    }

    private func dateText(_ e: ShiftEvent) -> String {
        guard let d = e.startDate else { return "日付なし" }
        let p = Rules.ymd(d)
        return "\(p.month)/\(p.day)(\(Self.weekdays[Rules.weekday(d)]))"
    }

    private func selectionBar(_ list: [ShiftEvent]) -> some View {
        HStack(spacing: 10) {
            Button(chosenCount == list.count ? "選択を外す" : "全て選択") {
                selected = chosenCount == list.count ? [] : Set(list.map(\.id))
            }
            .buttonStyle(.bordered)
            Spacer(minLength: 0)
            Button("ラベルを変更") { showMove = true }
                .buttonStyle(.borderedProminent)
                .disabled(chosenCount == 0)
            Button("削除", role: .destructive) { confirmDelete = true }
                .buttonStyle(.bordered)
                .disabled(chosenCount == 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func move(to id: String?) {
        store.setLabel(eventIds: selected, to: id)
        finishSelection()
    }

    private func finishSelection() {
        selected = []
        selecting = false
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
                    }
                }
            }
            .navigationTitle(isNew ? "ラベルを追加" : "ラベルを編集")
            .keyboardDismissBar()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "追加" : "保存") { save() }.disabled(!canSave)
                }
            }
            .alert("このラベルを削除しますか?", isPresented: $confirmDelete) {
                Button("キャンセル", role: .cancel) {}
                Button("削除", role: .destructive) {
                    store.deleteLabel(id: label.id)
                    dismiss()
                }
            } message: {
                Text("\(store.labelEventCount(label.id))件の予定は「指定なし」に変更されます。")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(.systemGroupedBackground))
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
