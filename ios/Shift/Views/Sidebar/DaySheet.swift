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
    let onSelectEvent: (ShiftEvent) -> Void
    let onSelectPayday: (String) -> Void
    let onAddEvent: (String) -> Void

    init(date: String, canAdd: Bool = true, onSelectEvent: @escaping (ShiftEvent) -> Void,
         onSelectPayday: @escaping (String) -> Void = { _ in }, onAddEvent: @escaping (String) -> Void = { _ in }) {
        self.date = date
        self.canAdd = canAdd
        self.onSelectEvent = onSelectEvent
        self.onSelectPayday = onSelectPayday
        self.onAddEvent = onAddEvent
    }

    private var dateText: String {
        let p = Rules.ymd(date)
        let wd = Rules.weekdayLabels(startMonday: false)[Rules.weekday(date)]
        return "\(p.year)年\(p.month)月\(p.day)日 (\(wd))"
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 右上の ⊕ で、この日に予定を追加する(閉じるのは、画面を下げる)
                if canAdd {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            dismiss()
                            onAddEvent(date)
                        } label: { Image(systemName: "plus") }
                            .accessibilityLabel("この日に予定を追加")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(.systemBackground))
        // 半分の高さのあいだは、後ろのカレンダーにも触れる(予定をつかんで、カレンダーへ運べるように)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationDragIndicator(.visible)
    }

    /// 左へスワイプして出す「削除」を出せる予定か(動かせる予定と同じ。ほかの人の予定は、出さない)
    private func canDelete(_ ev: ShiftEvent) -> Bool {
        shared.isOpen ? shared.canDrag(ev.id) : !store.isOverlay(ev.id)
    }

    private func delete(_ ev: ShiftEvent) {
        if shared.isOpen {
            Task { _ = await shared.delete(id: ev.id) }
        } else {
            store.delete(id: ev.id)
        }
    }

    @ViewBuilder
    private func dayContent(summary: DaySummary, annivs: [Anniversary]) -> some View {
        VStack(spacing: 0) {
                Text(dateText)
                    .font(.app(14))
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemBackground))
                badges(summary)
                if summary.events.isEmpty && annivs.isEmpty {
                    Spacer()
                    Text("予定はありません")
                        .foregroundStyle(Color.secondary)
                    Spacer()
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
                                .onTapGesture {
                                    dismiss()
                                    onSelectEvent(row.event)
                                }
                                .accessibilityAddTraits(.isButton)
                                // 長押ししてつかむと、カレンダー上のバーと同じに動かせる(動かせない予定は、詳細が開くだけ)
                                .eventDragSource(row.event) { ev in
                                    dismiss()
                                    onSelectEvent(ev)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if canDelete(row.event) {
                                        Button(role: .destructive) { delete(row.event) } label: {
                                            Label("削除", systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
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
