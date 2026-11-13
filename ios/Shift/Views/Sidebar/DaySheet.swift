import SwiftUI

struct DaySheet: View {
    @Environment(Store.self) private var store
    @Environment(Holidays.self) private var holidays
    @Environment(\.dismiss) private var dismiss
    @Environment(SharedViewState.self) private var shared

    /// 表示中の日
    let date: String
    /// 詳細を開いている記念日・誕生日
    @State private var annivId: String?
    /// 変更・削除を開いているアラーム
    @State private var editingAlarm: AlarmEntry?
    /// 共有カレンダーなど、見るだけのときは false(予定追加のボタンを出さない)
    let canAdd: Bool
    let onSelectPayday: (String) -> Void
    /// 「この日に予定を追加」や、予定を押したときに開く画面の中身を作る(一覧は閉じずに、その上に重ねて開く)
    let makeAddTarget: (String) -> DayEditTarget?
    let makeEditTarget: (ShiftEvent) -> DayEditTarget?
    let addEditor: (DayEditTarget) -> AnyView
    /// 隣の日へ(-1: 前の日 / 1: 次の日)。日付の見出しや、予定のないところを左右にスワイプしたとき
    let onStep: (Int) -> Void
    /// シートの高さ(半分か全画面か)。日を移っても変わらないよう、開いている側で持つ
    @Binding var detent: PresentationDetent
    /// 全画面に広げるかを、もう決めたか(開いたとき・日を移ったときの 1 回だけ。自分で縮めたら、そのまま)
    @State private var sizeChecked = false
    @State private var adding: DayEditTarget?
    /// 編集を開いている開始・締切・タスク
    @State private var taskEdit: TaskEditTarget?

    init(date: String, canAdd: Bool = true,
         onSelectPayday: @escaping (String) -> Void = { _ in },
         makeAddTarget: @escaping (String) -> DayEditTarget? = { _ in nil },
         makeEditTarget: @escaping (ShiftEvent) -> DayEditTarget? = { _ in nil },
         addEditor: @escaping (DayEditTarget) -> AnyView = { _ in AnyView(EmptyView()) },
         onStep: @escaping (Int) -> Void = { _ in },
         detent: Binding<PresentationDetent> = .constant(.medium)) {
        self.date = date
        self.canAdd = canAdd
        self.onSelectPayday = onSelectPayday
        self.makeAddTarget = makeAddTarget
        self.makeEditTarget = makeEditTarget
        self.addEditor = addEditor
        self.onStep = onStep
        _detent = detent
    }

    /// 1 行の高さの目安(予定は、時刻とタイトルの 2 段ぶん。記念日・開始締切は 1 段)
    private static let eventRowHeight: CGFloat = 56
    private static let smallRowHeight: CGFloat = 48

    /// 半分の高さで、予定が出しきれないときは、全画面に広げる(普段は半分のまま。自分で縮めたあとは広げ直さない)
    private func expandIfNeeded(listHeight: CGFloat, events: Int, others: Int) {
        guard !sizeChecked, listHeight > 0 else { return }
        sizeChecked = true
        guard detent == .medium else { return }
        let needed = CGFloat(events) * Self.eventRowHeight + CGFloat(others) * Self.smallRowHeight
        if needed > listHeight { detent = .large }
    }

    /// 日付の見出し。月日を大きく、曜日は土日祝の色で。その上に、年(真ん中)と「今日」(月日の左端にそろえる)。祝日名は下に小さく。
    /// 見出しを左右にスワイプして、隣の日へ(矢印は出さない。全画面のとき、戻るボタンに見えてしまうため)
    private var dateHeader: some View {
        let p = Rules.ymd(date)
        let holiday = holidays.name(on: date)
        let type = Rules.dayType(date, isHoliday: holiday != nil)
        let wd = Rules.weekdayLabels(startMonday: false)[Rules.weekday(date)]
        return HStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 1) {
                // 月日の上に、年(月日の真ん中)と「今日」(月日の左端にそろえる)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(p.month)月\(p.day)日")
                        .font(.app(24, weight: .bold).monospacedDigit())
                    Text("(\(wd))")
                        .font(.app(17, weight: .semibold))
                        .foregroundStyle(type == .normal ? Color.secondary : type.color)
                }
                .padding(.top, 16)
                .overlay(alignment: .top) {
                    Text(verbatim: "\(p.year)年").font(.app(11)).foregroundStyle(.secondary)
                }
                .overlay(alignment: .topLeading) {
                    if date == Rules.today() {
                        Text("今日")
                            .font(.app(10, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Theme.accent, in: Capsule())
                    }
                }
                if let holiday {
                    Text(holiday).font(.app(11, weight: .semibold)).foregroundStyle(type.color)
                }
            }
            .accessibilityElement(children: .combine)
            // VoiceOver では、上下のスワイプで隣の日へ
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(1)
                case .decrement: step(-1)
                @unknown default: break
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .gesture(daySwipe)
    }

    /// 左へスワイプで次の日、右へスワイプで前の日(横に大きく動かしたときだけ。縦のスクロールやシートの上げ下げとは分ける)
    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { v in
                let dx = v.translation.width, dy = v.translation.height
                guard abs(dx) > 50, abs(dx) > abs(dy) * 1.5 else { return }
                step(dx < 0 ? 1 : -1)
            }
    }

    private func step(_ delta: Int) {
        UISelectionFeedbackGenerator().selectionChanged()
        onStep(delta)
    }

    var body: some View {
        let summary = store.daySummary(date: date, isHoliday: { holidays.name(on: $0) != nil })
        let annivs = store.anniversaries(on: date)
        NavigationStack {
            VStack(spacing: 0) {
                dayContent(summary: summary, annivs: annivs)
            }
            .clipped()
            // 予定をつかんでシートの外(カレンダー)へ出したら、シートを閉じて、いつものドラッグの流れに続ける
            .onChange(of: DragState.shared.isDragging) { _, dragging in
                if dragging { dismiss() }
            }
            .navigationDestination(item: $annivId) { AnniversaryDetail(id: $0, asOf: date) }
            .sheet(item: $editingAlarm) { AlarmEditSheet(entry: $0) }
            .sheet(item: $adding) { addEditor($0) }
            .sheet(item: $taskEdit) { TaskEditor(original: $0.task, isNew: $0.isNew) }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 右上の ⊕ で、この日に予定を追加する(閉じるのは、画面を下げる)
                if canAdd { addToolbarItem }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationBackground(Color(.systemBackground))
        // 半分の高さのあいだは、後ろのカレンダーにも触れる(予定をつかんで、カレンダーへ運べるように)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationDragIndicator(.visible)
    }

    /// カレンダー右上の ⊕ と同じ、丸いボタン
    private var addButton: some View {
        Button {
            adding = makeAddTarget(date)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 36, height: 36)
                .background(Theme.accent, in: Circle())
        }
        .accessibilityLabel("この日に予定を追加")
    }

    /// iOS 26 では、ツールバーのボタンに、システムの丸い下地が付くので、外す(自前の丸だけにする)
    @ToolbarContentBuilder
    private var addToolbarItem: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) { addButton }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) { addButton }
        }
    }

    /// 左へスワイプして出す「削除」を出せる予定か(動かせる予定と同じ。ほかの人の予定は、出さない)
    private func canDelete(_ ev: ShiftEvent) -> Bool {
        shared.isOpen ? shared.canDrag(ev.id) : !store.isOverlay(ev.id)
    }

    private func delete(_ ev: ShiftEvent) {
        if shared.isOpen {
            // 共有に出した自分の予定は、自分のカレンダーの予定として消す
            if shared.ownEventId(for: ev.id) != nil {
                shared.deleteOwn(id: ev.id)
            } else {
                Task { _ = await shared.delete(id: ev.id) }
            }
        } else {
            store.delete(id: ev.id)
        }
    }

    @ViewBuilder
    private func dayContent(summary: DaySummary, annivs: [Anniversary]) -> some View {
        let taskRows = store.taskRows(on: date)
        VStack(spacing: 0) {
                dateHeader
                badges(summary)
                    .contentShape(Rectangle())
                    .gesture(daySwipe)
                if summary.events.isEmpty && annivs.isEmpty && taskRows.isEmpty {
                    // 予定のない日は、どこを左右にスワイプしても、隣の日へ
                    Text("予定はありません")
                        .foregroundStyle(Color.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(daySwipe)
                } else {
                    List {
                        // 記念日・誕生日(タップで詳細。メモもそこで見られる)
                        ForEach(annivs) { a in
                            // 横にスワイプして指を離したときに開かないよう、ボタンではなく「タップ」だけで開く
                            HStack(spacing: 10) {
                                    AnniversaryIcon(icon: a.icon, color: a.color, size: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(a.name).font(.app(17))
                                        if !a.memo.isEmpty {
                                            Text(a.memo).font(.app(12)).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    if let e = a.elapsedText(asOf: date) {
                                        Text(e).font(.app(15, weight: .semibold).monospacedDigit())
                                            .foregroundStyle(Color(hex: a.color))
                                    }
                                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { annivId = a.id }
                            .accessibilityAddTraits(.isButton)
                        }
                        ForEach(summary.events) { row in
                            // 横にスワイプして指を離したときに開かないよう、ボタンではなく「タップ」だけで開く
                            eventRow(row)
                                .contentShape(Rectangle())
                                .onTapGesture { adding = makeEditTarget(row.event) }
                                .accessibilityAddTraits(.isButton)
                                // 長押ししてつかむと、カレンダー上のバーと同じに動かせる(動かせない予定は、詳細が開くだけ)
                                .eventDragSource(row.event, barPreview: true) { ev in
                                    adding = makeEditTarget(ev)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if canDelete(row.event) {
                                        Button(role: .destructive) { delete(row.event) } label: {
                                            swipeDeleteLabel
                                        }
                                        .tint(swipeDeleteTint)
                                    }
                                }
                        }
                        // 開始・締切(チェックを付けたものは、取消線のまま残る)
                        ForEach(taskRows) { row in
                            TaskRowView(row: row) {
                                withAnimation(.snappy) { store.toggleTaskDone(id: row.task.id) }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { taskEdit = TaskEditTarget(task: row.task, isNew: false) }
                            .accessibilityAddTraits(.isButton)
                            // 長押ししてつかむと、予定と同じように、カレンダー上の日へ動かせる(開始・締切の、その側だけ)
                            .taskDragSource(row: row, store: store) { taskEdit = TaskEditTarget(task: row.task, isNew: false) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { store.deleteTask(id: row.task.id) } label: {
                                    swipeDeleteLabel
                                }
                                .tint(swipeDeleteTint)
                            }
                        }
                        // 予定の下の余白。左右にスワイプで、隣の日へ(予定の行は、左へのスワイプが削除なので使わない)。
                        // スクロールを止めないよう、ほかのジェスチャーと同時に受ける
                        Color.clear
                            .frame(height: 160)
                            .contentShape(Rectangle())
                            .simultaneousGesture(daySwipe)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .accessibilityHidden(true)
                    }
                    .listStyle(.plain)
                    // 開いたとき(日を移ったときも)、半分の高さで予定が出しきれなければ、全画面に広げる
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { h in
                        expandIfNeeded(listHeight: h, events: summary.events.count, others: annivs.count + taskRows.count)
                    }
                }
        }
    }

    /// チップの文字。「予定の○前」のアラームは、鳴る時刻のあとに、その長さを添える(例: 16:00(予定2時間前))
    private static func alarmChipText(_ entry: AlarmEntry) -> String {
        let time = alarmTime(entry)
        guard entry.kind == .beforeShift else { return time }
        return time + "(" + AlarmPreset(kind: .beforeShift, minutes: entry.minutes).label + ")"
    }

    private static func alarmTime(_ entry: AlarmEntry) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: entry.fireTime))
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    @ViewBuilder
    private func badges(_ summary: DaySummary) -> some View {
        let alarms = store.alarmEntries(on: date)
        if !summary.paydays.isEmpty || !alarms.isEmpty {
            HStack(spacing: 6) {
                ForEach(summary.paydays) { r in
                    Button {
                        dismiss()
                        onSelectPayday(date)
                    } label: {
                    Text("給料日 \(Money.yen(r.amount))")
                        .font(.app(11, weight: .semibold))
                        .foregroundStyle(Theme.payText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Theme.payFill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                ForEach(alarms) { entry in
                    // タップで、時刻・スヌーズの変更と、削除
                    Button { editingAlarm = entry } label: {
                        Label(Self.alarmChipText(entry), systemImage: "bell.fill")
                            .font(.app(11, weight: .semibold))
                            .foregroundStyle(Theme.alarm)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Theme.alarm.opacity(0.16), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("アラーム \(Self.alarmChipText(entry))。タップで変更・削除")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func paydayRow(_ r: Store.PaymentRow) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text("給料日")
                .font(.app(13, weight: .bold))
                .foregroundStyle(Theme.payText)
                .frame(width: 64, alignment: .trailing)
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.payText.opacity(0.7))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(Money.yen(r.amount))
                    .font(.app(17, weight: .bold))
                    .foregroundStyle(Theme.payText)
                Text(r.workplace.name)
                    .font(.app(17))
                    .foregroundStyle(Color.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func eventRow(_ row: DayEventRow) -> some View {
        let ev = row.event
        return HStack(alignment: .center, spacing: 8) {
            timeColumn(row)
                .frame(width: 64, alignment: .trailing)
            RoundedRectangle(cornerRadius: 2)
                .fill(EventColor.fill(ev.color))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(ev.title)
                    .font(.app(17))
                    .foregroundStyle(Color.primary)
                if !ev.memo.isEmpty {
                    Text(ev.memo)
                        .font(.app(12))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            AttachmentIcons(imageId: ev.imageId, url: ev.url)
            // 共有カレンダーでは、共有に出した予定は共有した人のアバター、共有カレンダーの中で作った予定は、そのカレンダーのアイコンをつける
            if shared.isOpen {
                if shared.event(ev.id)?.isCalendarOwned == true {
                    if let cal = shared.calendar { CalendarBadge(icon: cal.icon, size: 28) }
                } else if let o = shared.owner(of: ev.id) {
                    UserAvatar(uid: o.uid, name: o.name, avatar: o.avatar, size: 28)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func timeColumn(_ row: DayEventRow) -> some View {
        let ev = row.event
        if row.isAllDay {
            Text("終日")
                .font(.app(16))
                .foregroundStyle(Color.primary)
        } else if row.isContinuation {
            VStack(alignment: .trailing, spacing: 2) {
                Text("前日から")
                    .font(.app(11))
                    .foregroundStyle(Color.secondary)
                if let e = ev.endTime {
                    Text(e)
                        .font(.app(14).monospacedDigit())
                        .foregroundStyle(Color.secondary)
                }
            }
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                Text(ev.startTime ?? "")
                    .font(.app(16).monospacedDigit())
                    .foregroundStyle(Color.primary)
                if let e = ev.endTime {
                    Text(e)
                        .font(.app(14).monospacedDigit())
                        .foregroundStyle(Color.secondary)
                }
            }
        }
    }
}
