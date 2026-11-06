import SwiftUI

struct SharedEditTarget: Identifiable {
    let id = UUID()
    let event: SharedEvent
    let isNew: Bool
}

/// 共有カレンダーの中で作る予定の編集。参加者全員が見られて、直せる。給料やメモは持たない
struct SharedEventEditor: View {
    @Environment(SharedViewState.self) private var shared
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let target: SharedEditTarget
    @State private var title: String
    @State private var allDay: Bool
    /// 日付を決めるか。決めないと「未配置」になり、あとで、カレンダーの日にドラッグして置く
    @State private var hasDate: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var color: String
    @State private var saving = false
    @State private var failed = false
    @State private var confirmDelete = false

    init(target: SharedEditTarget) {
        self.target = target
        let e = target.event
        _title = State(initialValue: e.title)
        _allDay = State(initialValue: e.allDay)
        _hasDate = State(initialValue: e.placed)
        _start = State(initialValue: Self.combine(e.startDate, e.startTime, fallbackHour: 9))
        _end = State(initialValue: Self.combine(e.endDate, e.endTime, fallbackHour: 18))
        _color = State(initialValue: e.color)
    }

    /// "2026-11-10" と "09:30" から日時を作る(時刻が無ければ、指定の時)
    static func combine(_ date: String, _ time: String?, fallbackHour: Int) -> Date {
        let base = Rules.parse(date) ?? Date()
        let parts = (time ?? "").split(separator: ":").compactMap { Int($0) }
        let (h, m) = parts.count == 2 ? (parts[0], parts[1]) : (fallbackHour, 0)
        return Calendar.current.date(bySettingHour: min(23, h), minute: m, second: 0, of: base) ?? base
    }

    private static func timeText(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private var endsBeforeStart: Bool {
        // 日付を決めない予定は、時間だけなので、夜をまたぐ時間も入れられる
        guard hasDate else { return false }
        return allDay ? Rules.format(end) < Rules.format(start) : end < start
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !endsBeforeStart && !saving
    }

    private func built() -> SharedEvent {
        let e = target.event
        var out = SharedEvent(id: e.id, ownerUid: e.ownerUid, sourceKey: e.sourceKey,
                              title: title.trimmingCharacters(in: .whitespaces),
                              startDate: hasDate ? Rules.format(start) : "", endDate: hasDate ? Rules.format(end) : "",
                              startTime: allDay ? nil : Self.timeText(start), endTime: allDay ? nil : Self.timeText(end),
                              allDay: allDay, name: e.name, color: color, barTime: e.barTime)
        out.placed = hasDate
        return out
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("タイトル(必須)", text: $title)
                    ColorRow(color: $color, recent: store.customColors, onDeleteRecent: { store.removeCustomColor($0) })
                } footer: {
                    Text("この予定は、共有カレンダーの参加者全員が見られて、直せます。給料やメモは持ちません。日付を決めない予定は、下の未配置エリアに入ります。")
                }
                Section {
                    Toggle("日付を決める", isOn: $hasDate)
                    Toggle("終日", isOn: $allDay)
                    if hasDate {
                        DatePicker("開始", selection: $start, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                        DatePicker("終了", selection: $end, displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                    } else if !allDay {
                        DatePicker("開始", selection: $start, displayedComponents: [.hourAndMinute])
                        DatePicker("終了", selection: $end, displayedComponents: [.hourAndMinute])
                    }
                    if endsBeforeStart {
                        Text("終了は開始より前には設定できません")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                if failed {
                    Section { Text("保存できませんでした。通信を確認してください。").foregroundStyle(.red) }
                }
                if !target.isNew {
                    Section {
                        Button("削除", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .navigationTitle(target.isNew ? "共有カレンダーに追加" : "共有の予定を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(target.isNew ? "追加" : "保存") {
                        Task {
                            saving = true
                            failed = false
                            if await shared.save(built()) {
                                store.rememberColor(color)
                                dismiss()
                            } else {
                                failed = true
                            }
                            saving = false
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .onChange(of: start) { old, new in
                // 開始を動かしたら、終了も同じだけ動かす(長さを保つ)
                end = end.addingTimeInterval(new.timeIntervalSince(old))
            }
            .confirmationDialog("この予定を削除しますか?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    Task {
                        if await shared.delete(id: target.event.id) { dismiss() } else { failed = true }
                    }
                }
            } message: {
                Text("参加者全員のカレンダーから消えます。")
            }
        }
        .presentationDetents([.large])
    }
}
