import SwiftUI
import UIKit

struct TaskEditTarget: Identifiable {
    let task: TaskItem
    let isNew: Bool
    var id: String { task.id }
}

/// 開始・締切・タスクの追加と編集。開始と締切のそれぞれを入れる・入れないが選べて、どちらも入れないと「タスク」になる
struct TaskEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let original: TaskItem
    let isNew: Bool

    @State private var title: String
    @State private var color: String
    @State private var hasStart: Bool
    @State private var startDay: Date
    @State private var startTimed: Bool
    @State private var startClock: Date
    @State private var hasDue: Bool
    @State private var dueDay: Date
    @State private var dueTimed: Bool
    @State private var dueClock: Date
    @State private var confirmDelete = false

    init(original: TaskItem, isNew: Bool) {
        self.original = original
        self.isNew = isNew
        _title = State(initialValue: original.title)
        _color = State(initialValue: original.color)
        _hasStart = State(initialValue: original.hasStart)
        _startDay = State(initialValue: original.startDate.flatMap(Rules.parse) ?? Rules.parse(Rules.today()) ?? Date())
        // 時刻は、最初はどちらもオン(すでにある項目は、その通り)
        _startTimed = State(initialValue: isNew ? true : original.startTime != nil)
        _startClock = State(initialValue: Self.clock(original.startTime, fallback: (9, 0)))
        _hasDue = State(initialValue: original.hasDue)
        _dueDay = State(initialValue: original.dueDate.flatMap(Rules.parse) ?? original.startDate.flatMap(Rules.parse) ?? Rules.parse(Rules.today()) ?? Date())
        _dueTimed = State(initialValue: isNew ? true : original.dueTime != nil)
        _dueClock = State(initialValue: Self.clock(original.dueTime, fallback: (18, 0)))
    }

    private static func clock(_ text: String?, fallback: (Int, Int)) -> Date {
        let p = (text ?? "").split(separator: ":").compactMap { Int($0) }
        let (h, m) = p.count == 2 ? (p[0], p[1]) : fallback
        return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
    }

    private static func timeText(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var startText: String? { hasStart ? Rules.format(startDay) : nil }
    private var dueText: String? { hasDue ? Rules.format(dueDay) : nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("タイトル(必須)", text: $title)
                    ColorRow(color: $color, recent: store.customColors, onDeleteRecent: { store.removeCustomColor($0) })
                    // 予定バーの見た目。色の下に出す
                    HStack(alignment: .center, spacing: 8) {
                        Text("予定バーの見た目").lineLimit(1).fixedSize()
                        Spacer(minLength: 0)
                        TaskLookPreview(title: title.isEmpty ? "タイトル" : title, color: color, start: startText, due: dueText)
                    }
                }
                Section {
                    Toggle("開始", isOn: $hasStart.animation())
                    if hasStart {
                        DatePicker("日付", selection: $startDay, displayedComponents: .date)
                        Toggle("時間も設定", isOn: $startTimed.animation())
                        if startTimed { DatePicker("時刻", selection: $startClock, displayedComponents: .hourAndMinute) }
                    }
                }
                Section {
                    Toggle("締切", isOn: $hasDue.animation())
                    if hasDue {
                        DatePicker("日付", selection: $dueDay, in: (hasStart ? startDay : Date.distantPast)..., displayedComponents: .date)
                        Toggle("時間も設定", isOn: $dueTimed.animation())
                        if dueTimed { DatePicker("時刻", selection: $dueClock, displayedComponents: .hourAndMinute) }
                    }
                } footer: {
                    if !hasStart && !hasDue {
                        Text("開始も締切も指定がない場合は「タスク」として保存されます。")
                    }
                }
                if !isNew {
                    Section {
                        Button("削除", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "開始・締切予定を追加" : "開始・締切予定を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "追加" : "保存") { commit() }.disabled(!canSave)
                }
            }
            .onChange(of: startDay) { _, new in
                if hasDue, dueDay < new { dueDay = new }
            }
            .alert("この項目を削除しますか?", isPresented: $confirmDelete) {
                Button("キャンセル", role: .cancel) {}
                Button("削除", role: .destructive) {
                    store.deleteTask(id: original.id)
                    dismiss()
                }
            }
        }
    }

    private func commit() {
        var t = original
        t.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        t.color = color
        t.startDate = startText
        t.startTime = hasStart && startTimed ? Self.timeText(startClock) : nil
        t.dueDate = dueText
        t.dueTime = hasDue && dueTimed ? Self.timeText(dueClock) : nil
        store.rememberColor(color)
        store.saveTask(t)
        dismiss()
    }
}

/// 「予定バーの見た目」: 月カレンダーでの開始・締切のタグを、その日付で見せる(最大 3 マス。予定の見た目と同じ決まり)
struct TaskLookPreview: View {
    let title: String
    let color: String
    let start: String?
    let due: String?
    @AppStorage(BarFontSize.monthKey) private var monthDelta = 0.0

    private let barH: CGFloat = 18

    private enum Column {
        case day(String)
        case omitted
    }

    private var dates: [String] { [start, due].compactMap { $0 } }

    private var columns: [Column] {
        guard let first = dates.min(), let last = dates.max() else { return [] }
        let days = max(1, Rules.daysBetween(first, last) + 1)
        switch days {
        case 1: return [.day(first)]
        case 2: return [.day(first), .day(last)]
        case 3: return [.day(first), .day(Rules.addDays(first, 1)), .day(last)]
        default: return [.day(first), .omitted, .day(last)]
        }
    }

    var body: some View {
        if dates.isEmpty {
            Text("カレンダーには出ません")
                .font(.app(11))
                .foregroundStyle(.secondary)
        } else {
            preview
        }
    }

    private var preview: some View {
        let colW = floor(UIScreen.main.bounds.width / 7)
        let omittedW = (colW * 0.7).rounded()
        let columns = self.columns
        let widths = columns.map { c -> CGFloat in if case .omitted = c { return omittedW } else { return colW } }
        let total = widths.reduce(0, +)
        let fontSize = max(5, FixedWidthTime.fitSize(width: colW - 2 - BarFontSize.sidePadding) + CGFloat(monthDelta))
        // 開始と締切が同じ日なら、同じマスに 2 本、重ねずに並べる
        let sameDay = start != nil && start == due
        let lanes = sameDay ? 2 : 1
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                ForEach(columns.indices, id: \.self) { i in
                    cell(columns[i])
                        .frame(width: widths[i], height: 15, alignment: .leading)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color(.separator).opacity(0.5)).frame(width: 0.5)
                        }
                }
            }
            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: total, height: CGFloat(lanes) * (barH + 2))
                if let s = start {
                    tag(isStart: true, at: x(of: s, widths: widths, columns: columns), width: colW, lane: 0, fontSize: fontSize)
                }
                if let d = due {
                    tag(isStart: false, at: x(of: d, widths: widths, columns: columns), width: colW, lane: sameDay ? 1 : 0, fontSize: fontSize)
                }
            }
        }
        .padding(.bottom, 2)
        .frame(width: total, alignment: .leading)
        .background(Color(.systemBackground))
        .overlay(Rectangle().strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("カレンダー上の見た目のプレビュー")
    }

    /// その日の列の左端。最初の日が先頭、最後の日が末尾の列
    private func x(of date: String, widths: [CGFloat], columns: [Column]) -> CGFloat {
        guard let first = dates.min() else { return 0 }
        if date == first { return 0 }
        return widths.dropLast().reduce(0, +)
    }

    private func tag(isStart: Bool, at x: CGFloat, width: CGFloat, lane: Int, fontSize: CGFloat) -> some View {
        TaskTagBar(title: title, color: color, isStart: isStart, height: barH, fontSize: fontSize)
            .frame(width: max(0, width - 2), height: barH)
            .offset(x: x + 1, y: CGFloat(lane) * (barH + 2))
    }

    @ViewBuilder
    private func cell(_ c: Column) -> some View {
        switch c {
        case .day(let ds):
            Text("\(Rules.ymd(ds).day)")
                .font(.app(10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        case .omitted:
            Text("〜")
                .font(.app(10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }
}
