import SwiftUI
import UIKit

struct TaskEditTarget: Identifiable {
    let task: TaskItem
    let isNew: Bool
    var id: String { task.id }
}

/// 開始・締切・タスクの追加と編集。開始と締切のそれぞれを入れる・入れないが選べて、どちらも入れないと「タスク」になる。
/// 時刻の入力(ホイール・数字キーボード・キーボードを閉じるボタン)は、通常の予定の編集画面と同じ
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
    @State private var startTime: String
    @State private var hasDue: Bool
    @State private var dueDay: Date
    @State private var dueTimed: Bool
    @State private var dueTime: String
    @State private var confirmDelete = false
    @State private var openPanel: TimePanel?
    @State private var typed = ""
    @FocusState private var focusedField: Field?
    /// キーボードが出たあとに見せたい行。出るのが遅れても、出た時点でもう一度スクロールする
    @State private var scrollTarget: String?

    enum Field: Hashable { case title, startTime, dueTime }
    enum TimePanel: Hashable { case start, due }

    init(original: TaskItem, isNew: Bool) {
        self.original = original
        self.isNew = isNew
        _title = State(initialValue: original.title)
        _color = State(initialValue: original.color)
        _hasStart = State(initialValue: original.hasStart)
        _startDay = State(initialValue: original.startDate.flatMap(Rules.parse) ?? Rules.parse(Rules.today()) ?? Date())
        // 最初は、開始オフ・時間オフ、締切オン・時間オン(すでにある項目は、その通り)
        _startTimed = State(initialValue: isNew ? false : original.startTime != nil)
        _startTime = State(initialValue: original.startTime ?? "09:00")
        _hasDue = State(initialValue: original.hasDue)
        _dueDay = State(initialValue: original.dueDate.flatMap(Rules.parse) ?? original.startDate.flatMap(Rules.parse) ?? Rules.parse(Rules.today()) ?? Date())
        _dueTimed = State(initialValue: isNew ? true : original.dueTime != nil)
        _dueTime = State(initialValue: original.dueTime ?? "18:00")
    }

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var startText: String? { hasStart ? Rules.format(startDay) : nil }
    private var dueText: String? { hasDue ? Rules.format(dueDay) : nil }

    private static let titleRowId = "titleRow"

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    Section {
                        TextField("タイトル(必須)", text: $title)
                            .focused($focusedField, equals: .title)
                            .id(Self.titleRowId)
                        ColorRow(color: $color, recent: store.customColors, onDeleteRecent: { store.removeCustomColor($0) }, taskLook: true)
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
                            Toggle("時間も設定", isOn: $startTimed.animation())
                            dateRow(.start)
                            timePanelRows(.start)
                        }
                    }
                    Section {
                        Toggle("締切", isOn: $hasDue.animation())
                        if hasDue {
                            Toggle("時間も設定", isOn: $dueTimed.animation())
                            dateRow(.due)
                            timePanelRows(.due)
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
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: openPanel) { _, new in
                    guard let new else { return }
                    scrollToBottom(panelBottomId(new), proxy: proxy)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                    guard let id = scrollTarget else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
                    scrollTarget = nil
                }
                .onChange(of: focusedField) { old, new in
                    if new == nil { scrollTarget = nil }
                    if new == .title { scrollToBottom(Self.titleRowId, proxy: proxy) }
                    guard let old, let oldPanel = panel(for: old), openPanel == oldPanel else { return }
                    if new == nil || panel(for: new!) == nil { closeTimePanel() }
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
            .keyboardDismissBar { closeTimePanel() }
            .onChange(of: startDay) { _, new in
                if hasDue, dueDay < new { dueDay = new }
            }
            // 時間や日付の入力を閉じてしまう操作(スイッチを切る)では、開いている時刻の入力も閉じる
            .onChange(of: hasStart) { _, on in if !on, openPanel == .start { closeTimePanel() } }
            .onChange(of: startTimed) { _, on in if !on, openPanel == .start { closeTimePanel() } }
            .onChange(of: hasDue) { _, on in if !on, openPanel == .due { closeTimePanel() } }
            .onChange(of: dueTimed) { _, on in if !on, openPanel == .due { closeTimePanel() } }
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
        t.startTime = hasStart && startTimed ? startTime : nil
        t.dueDate = dueText
        t.dueTime = hasDue && dueTimed ? dueTime : nil
        store.rememberColor(color)
        store.saveTask(t)
        dismiss()
    }

    // MARK: 日付の行

    /// 「日付」の行。時間をオンにしたときは、同じ行に、日付と時刻を並べる(通常の予定の「開始」の行と同じ)
    private func dateRow(_ p: TimePanel) -> some View {
        HStack(spacing: 8) {
            Text("日付")
            Spacer()
            if p == .start {
                DatePicker("", selection: $startDay, displayedComponents: .date).labelsHidden()
            } else {
                DatePicker("", selection: $dueDay, in: (hasStart ? startDay : Date.distantPast)..., displayedComponents: .date).labelsHidden()
            }
            if timed(p) { timeChip(p) }
        }
    }

    private func timed(_ p: TimePanel) -> Bool { p == .start ? startTimed : dueTimed }

    // MARK: 時刻入力(通常の予定の編集画面と同じ)

    /// 開始・締切は、その日のうちの時刻(24:00 まで)
    private static let maxMinutes = 24 * 60

    private func timeValue(_ p: TimePanel) -> String { p == .start ? startTime : dueTime }

    private func setTime(_ p: TimePanel, _ t: String) {
        if p == .start { startTime = t } else { dueTime = t }
        typed = Self.digits(of: t)
    }

    private static func digits(of time: String) -> String { time.filter { $0.isASCII && $0.isNumber } }

    /// Form の行の出入りをアニメーションさせるとキーボードの表示と重なってカクつくので、即時に切り替える
    private func noAnimation(_ body: () -> Void) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t, body)
    }

    private func closeTimePanel() {
        scrollTarget = nil
        typed = ""
        focusedField = nil
        noAnimation { openPanel = nil }
    }

    private func toggleTimePanel(_ p: TimePanel) {
        let next: TimePanel? = openPanel == p ? nil : p
        typed = next == nil ? "" : Self.digits(of: timeValue(p))
        noAnimation { openPanel = next }
        focusedField = next.map(field(for:))
    }

    private func field(for p: TimePanel) -> Field { p == .start ? .startTime : .dueTime }

    private func panel(for f: Field) -> TimePanel? {
        switch f {
        case .startTime: return .start
        case .dueTime: return .due
        default: return nil
        }
    }

    private func panelBottomId(_ p: TimePanel) -> String { p == .start ? "startPanelBottom" : "duePanelBottom" }

    /// 行の展開とキーボードの表示が落ち着いてから、1回だけスクロールして下端を見せる
    /// (展開・キーボード・スクロールのアニメーションが重なるとカクつく)
    private func scrollToBottom(_ id: String, proxy: ScrollViewProxy) {
        scrollTarget = id
        for (n, delay) in [0.25, 0.6].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard scrollTarget == id else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
                if n == 1 { scrollTarget = nil }
            }
        }
    }

    /// チップの表示。入力途中なら打鍵中の数字を時刻の形で見せる
    private func chipText(_ p: TimePanel) -> String {
        guard openPanel == p, !typed.isEmpty, typed.count < 4 else { return timeValue(p) }
        return typed.count <= 2 ? typed : String(typed.prefix(2)) + ":" + String(typed.dropFirst(2))
    }

    private var typedBinding: Binding<String> {
        Binding(
            get: { typed },
            set: { input in
                guard let p = openPanel else { return }
                var digits = Self.digits(of: input)
                // 4桁そろった後の打鍵は、次の4桁の入力開始として受け付ける
                if digits.count > 4 { digits = String(digits.dropFirst(4).prefix(4)) }
                if digits.isEmpty {
                    setTime(p, "00:00")
                    typed = ""
                } else if digits.count == 4 {
                    if let t = Rules.parseTimeDigits(digits, maxMinutes: Self.maxMinutes) {
                        setTime(p, t)
                    } else {
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                        typed = Self.digits(of: timeValue(p))
                    }
                } else {
                    typed = digits
                }
            }
        )
    }

    private func timeChip(_ p: TimePanel) -> some View {
        let open = openPanel == p
        return Button { toggleTimePanel(p) } label: {
            Text(chipText(p))
                .font(.app(17).monospacedDigit())
                .foregroundStyle(open ? Theme.onAccent : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(open ? Theme.accent : Color(.secondarySystemFill)))
        }
        .buttonStyle(.borderless)
    }

    /// 時刻のチップを押したときに開く、ホイールと、数字キーボードの受け口
    @ViewBuilder
    private func timePanelRows(_ p: TimePanel) -> some View {
        if openPanel == p, timed(p) {
            VStack(spacing: 0) {
                wheelPanel(p)
                TextField("", text: typedBinding)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: field(for: p))
                    .frame(width: 1, height: 1)
                    .opacity(0.02)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .id(panelBottomId(p))
        }
    }

    private func wheelPanel(_ p: TimePanel) -> some View {
        let maxHour = Self.maxMinutes / 60
        let cur = Rules.minutes(timeValue(p)) ?? 0
        let curH = min(cur / 60, maxHour), curM = cur % 60
        var minuteItems = Rules.minuteOptions
        if !minuteItems.contains(curM) { minuteItems.append(curM); minuteItems.sort() }
        if curH >= maxHour { minuteItems = [0] }
        let hourBinding = Binding<Int>(
            get: { curH },
            set: { h in
                let m = h >= maxHour ? 0 : curM
                setTime(p, String(format: "%02d:%02d", h, m))
            })
        let minuteBinding = Binding<Int>(
            get: { curH >= maxHour ? 0 : curM },
            set: { m in setTime(p, String(format: "%02d:%02d", curH, m)) })
        return HStack(spacing: 0) {
            Picker("時", selection: hourBinding) {
                ForEach(Rules.hourOptions(maxHour: maxHour), id: \.self) { h in
                    Text(String(format: "%02d", h)).frame(maxWidth: .infinity, alignment: .trailing)
                        .tag(h)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            Text(":").font(.app(20).monospacedDigit())
            Picker("分", selection: minuteBinding) {
                ForEach(minuteItems, id: \.self) { m in
                    Text(String(format: "%02d", m)).frame(maxWidth: .infinity, alignment: .leading)
                        .tag(m)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
        }
        .frame(height: 140)
        .clipped()
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
                if let s = start, let d = due, s != d {
                    // 開始と締切をつなぐ点線
                    let xs = x(of: s, widths: widths, columns: columns) + colW
                    let xd = x(of: d, widths: widths, columns: columns)
                    Path { p in
                        p.move(to: CGPoint(x: xs + 2, y: barH / 2))
                        p.addLine(to: CGPoint(x: xd - 2, y: barH / 2))
                    }
                    .stroke(Color(hex: color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.1, 3.5]))
                }
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
