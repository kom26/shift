import SwiftUI
import UIKit

struct SharedEditTarget: Identifiable {
    let id = UUID()
    let event: SharedEvent
    let isNew: Bool
}

/// 「- 最終変更… -」を、1 行の小さな文字で出す(行を取らないよう、削除の見出しとして置く)
struct LastModifiedHeader: View {
    let line: String?

    var body: some View {
        if let line {
            Text(line)
                .font(.app(12))
                .foregroundStyle(.secondary)
                .textCase(nil)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }
}

/// 共有カレンダーの中で作る予定の編集。参加者全員が見られて、直せる。給料やメモは持たない
struct SharedEventEditor: View {
    @Environment(SharedViewState.self) private var shared
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    let target: SharedEditTarget
    /// 保存先を切り替えられるとき(自分のカレンダーと共有カレンダーのあいだで、予定を移せる)
    var flow: EditorFlow?
    @State private var title: String
    @State private var allDay: Bool
    /// 日付を決めるか。決めないと「未配置」になり、あとで、カレンダーの日にドラッグして置く
    @State private var hasDate: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var startTime: String
    @State private var endTime: String
    @State private var openPanel: TimePanel?
    /// 時刻を数字で打ち込んでいる途中の桁
    @State private var typed = ""
    @State private var lastValidEndDate: Date
    @State private var lastValidEndTime: String
    @State private var endWarningVisible = false
    @State private var endWarningTask: Task<Void, Never>?
    @FocusState private var focusedField: Field?
    @State private var color: String
    @State private var memo: String
    @State private var url: String
    @State private var imageId: String?
    /// フォームのどこかをタップするたびに増やす(メモ・画像・URL の空の欄を閉じる合図)
    @State private var outsideTap = 0
    @State private var attachments = AttachmentSession()
    @State private var saving = false
    @State private var failed = false
    @State private var confirmDelete = false

    enum Field: Hashable { case title, startTime, endTime }
    enum TimePanel: Hashable { case start, end }

    init(target: SharedEditTarget, flow: EditorFlow? = nil) {
        self.target = target
        self.flow = flow
        let e = target.event
        _title = State(initialValue: e.title)
        _allDay = State(initialValue: e.allDay)
        _hasDate = State(initialValue: e.placed && !e.startDate.isEmpty)
        let e0 = Self.combine(e.endDate, e.endTime, fallbackHour: 18)
        _start = State(initialValue: Self.combine(e.startDate, e.startTime, fallbackHour: 9))
        _end = State(initialValue: e0)
        _lastValidEndDate = State(initialValue: e0)
        // 24:30 のような、24 時を過ぎる時刻もそのまま持つ
        _startTime = State(initialValue: e.startTime.nonEmpty ?? "09:00")
        _endTime = State(initialValue: e.endTime.nonEmpty ?? "18:00")
        _lastValidEndTime = State(initialValue: e.endTime.nonEmpty ?? "18:00")
        _color = State(initialValue: e.color)
        _memo = State(initialValue: e.memo)
        _url = State(initialValue: e.url)
        _imageId = State(initialValue: e.imageId)
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
        if allDay { return Rules.format(end) < Rules.format(start) }
        return Rules.isEndBeforeStart(startDate: Rules.format(start), startTime: startTime,
                                      endDate: Rules.format(end), endTime: endTime)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !endsBeforeStart && !saving
    }

    private func built() -> SharedEvent {
        let e = target.event
        var out = SharedEvent(id: e.id, ownerUid: e.ownerUid, sourceKey: e.sourceKey,
                              title: title.trimmingCharacters(in: .whitespaces),
                              startDate: hasDate ? Rules.format(start) : "",
                              endDate: hasDate ? (Rules.resolveEndDate(start: Rules.format(start), end: Rules.format(end), allDay: allDay,
                                                                       startTime: allDay ? nil : startTime, endTime: allDay ? nil : endTime) ?? Rules.format(end)) : "",
                              startTime: allDay ? nil : startTime, endTime: allDay ? nil : endTime,
                              allDay: allDay, name: e.name, color: color, barTime: e.barTime)
        out.placed = hasDate
        out.memo = memo
        out.url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        out.imageId = imageId
        return out
    }

    // MARK: 時刻入力(自分の予定の編集と同じ。チップを押すとホイールが開き、数字を打っても入れられる)

    private func maxMinutes(_ p: TimePanel) -> Int { p == .start ? Rules.maxStartMinutes : Rules.maxEndMinutes }
    private func timeValue(_ p: TimePanel) -> String { p == .start ? startTime : endTime }
    private func field(for p: TimePanel) -> Field { p == .start ? .startTime : .endTime }
    private static func digits(of time: String) -> String { time.filter { $0.isASCII && $0.isNumber } }

    private func setTime(_ p: TimePanel, _ t: String) {
        if p == .start { startTime = t } else { endTime = t }
        typed = Self.digits(of: t)
    }

    /// Form の行の出入りをアニメーションさせるとキーボードの表示と重なってカクつくので、即時に切り替える
    private func noAnimation(_ body: () -> Void) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t, body)
    }

    private func closeTimePanel() {
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
                if digits.count > 4 { digits = String(digits.dropFirst(4).prefix(4)) }
                if digits.isEmpty {
                    setTime(p, "00:00")
                    typed = ""
                } else if digits.count == 4 {
                    if let t = Rules.parseTimeDigits(digits, maxMinutes: maxMinutes(p)) {
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

    private func wheelPanel(_ p: TimePanel) -> some View {
        let maxHour = maxMinutes(p) / 60
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
                    Text(String(format: "%02d", h)).frame(maxWidth: .infinity, alignment: .trailing).tag(h)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            Text(":").font(.app(20).monospacedDigit())
            Picker("分", selection: minuteBinding) {
                ForEach(minuteItems, id: \.self) { m in
                    Text(String(format: "%02d", m)).frame(maxWidth: .infinity, alignment: .leading).tag(m)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
        }
        .frame(height: 140)
        .clipped()
    }

    /// 日付を決めていないときの「日付未定」。押すと今日になる(自分の予定の追加と同じ)
    private func datePlaceholderChip(enabled: Bool) -> some View {
        Button {
            let d = Rules.parse(Rules.today()) ?? Date()
            lastValidEndDate = d
            start = d
            end = d
            hasDate = true
        } label: {
            Text("日付未定")
                .font(.app(17))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemFill)))
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    @ViewBuilder
    private func dayRow(_ label: String, _ value: Binding<Date>, from: Date? = nil) -> some View {
        HStack(spacing: 8) {
            Text(label)
            Spacer()
            if hasDate {
                if let from {
                    DatePicker("", selection: value, in: from..., displayedComponents: .date).labelsHidden()
                } else {
                    DatePicker("", selection: value, displayedComponents: .date).labelsHidden()
                }
            } else {
                datePlaceholderChip(enabled: from == nil)
            }
        }
    }

    /// 開始/終了の 1 行(日付と時刻のチップ)。時刻のチップを押すと、下にホイールが開く
    @ViewBuilder
    private func timeRow(_ p: TimePanel) -> some View {
        HStack(spacing: 8) {
            Text(p == .start ? "開始" : "終了")
            Spacer()
            if hasDate {
                if p == .start {
                    DatePicker("", selection: $start, displayedComponents: .date).labelsHidden()
                } else {
                    DatePicker("", selection: $end, in: start..., displayedComponents: .date).labelsHidden()
                }
            } else {
                datePlaceholderChip(enabled: p == .start)
            }
            timeChip(p)
        }
        if p == .end, endWarningVisible {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                Text("終了は開始より前には設定できません")
            }
            .font(.app(12))
            .foregroundStyle(Color.orange)
        }
        if openPanel == p {
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
        }
    }

    // MARK: 終了の表記切り替え

    private var endDaysFromStart: Int {
        hasDate ? Rules.daysBetween(Rules.format(start), Rules.format(end)) : 1
    }

    private func applyEnd(date: Date, time: String) {
        lastValidEndDate = date
        lastValidEndTime = time
        end = date
        endTime = time
    }

    @ViewBuilder
    private var endNotationHints: some View {
        if let sm = Rules.minutes(startTime), let em = Rules.minutes(endTime) {
            if em <= sm, em < 1440, endDaysFromStart == 1, let ext = Rules.extendedEndText(endTime) {
                notationHint("\(ext)とすると同日の予定として表記") { applyEnd(date: start, time: ext) }
            } else if em >= 1440 {
                let normal = String(format: "%02d:%02d", (em - 1440) / 60, (em - 1440) % 60)
                notationHint("\(normal)とすると日跨ぎ予定として表記") {
                    let next = hasDate ? (Rules.parse(Rules.addDays(Rules.format(end), 1)) ?? end) : end
                    applyEnd(date: next, time: normal)
                }
            }
        }
    }

    private func notationHint(_ text: String, change: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "questionmark.circle")
            Text(text)
            Spacer()
            Button("変更", action: change)
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.accent)
        }
        .font(.app(13))
        .foregroundStyle(.secondary)
    }

    private func syncLastValidEnd() {
        lastValidEndDate = end
        lastValidEndTime = endTime
    }

    /// 開始側の編集で終了が開始より前になったら終了日を進める(終日は 終了日 >= 開始日)
    private func normalizeEnd() {
        guard hasDate else { return }
        if allDay {
            if end < start { end = start }
            syncLastValidEnd()
            return
        }
        let next = Rules.normalizedEndDate(startDate: Rules.format(start), startTime: startTime,
                                           endDate: Rules.format(end), endTime: endTime)
        if next != Rules.format(end), let d = Rules.parse(next) {
            lastValidEndDate = d
            lastValidEndTime = endTime
            end = d
        } else {
            syncLastValidEnd()
        }
    }

    /// 終了側の編集の検証(自分の予定の編集と同じ)。時刻の編集は、開始より前なら終了日を進める。
    /// 終了日の編集で開始より前になるときは、直前の日付へ戻して警告する
    private func validateEndEdit() {
        guard hasDate, !allDay else { syncLastValidEnd(); return }
        let dateChanged = Rules.format(end) != Rules.format(lastValidEndDate)
        let timeChanged = endTime != lastValidEndTime
        guard dateChanged || timeChanged else { return }
        if timeChanged {
            let next = Rules.normalizedEndDate(startDate: Rules.format(start), startTime: startTime,
                                               endDate: Rules.format(end), endTime: endTime)
            if next != Rules.format(end), let d = Rules.parse(next) {
                lastValidEndDate = d
                lastValidEndTime = endTime
                end = d
            } else {
                syncLastValidEnd()
            }
        } else if Rules.isEndBeforeStart(startDate: Rules.format(start), startTime: startTime,
                                         endDate: Rules.format(end), endTime: endTime) {
            end = lastValidEndDate
            typed = ""
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            endWarningTask?.cancel()
            withAnimation { endWarningVisible = true }
            endWarningTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard !Task.isCancelled else { return }
                withAnimation { endWarningVisible = false }
            }
        } else {
            syncLastValidEnd()
        }
    }

    /// 予定バーの見た目のプレビュー用(月カレンダーで、この予定のバーがどう見えるか)
    private var previewEvent: ShiftEvent {
        let e = built()
        var p = ShiftEvent.newUnplaced()
        p.title = e.title.isEmpty ? "タイトル" : e.title
        p.color = e.color
        p.ownColor = true
        p.barShowsTitle = true
        p.placed = e.placed
        p.startDate = e.placed ? e.startDate : nil
        p.endDate = e.placed ? e.endDate : nil
        p.allDay = e.allDay
        p.startTime = e.startTime
        p.endTime = e.endTime
        return p
    }

    /// 画像の置き場にする共有カレンダーの ID(保存先を切り替えているときは、切り替え先)
    private var attachmentCalendarId: String? {
        if let flow, !flow.isAtOrigin, let cid = flow.destination { return cid }
        return shared.calendar?.id
    }

    var body: some View {
        NavigationStack {
            Form {
                if let flow { DestinationSection(flow: flow, draft: { .shared(built()) }) }
                Section {
                    TextField("タイトル(必須)", text: $title)
                        .focused($focusedField, equals: .title)
                    ColorRow(color: $color, recent: store.customColors, onDeleteRecent: { store.removeCustomColor($0) })
                    // 予定バーの見た目(自分の予定の編集と同じ)
                    HStack(alignment: .center, spacing: 8) {
                        Text("予定バーの見た目").lineLimit(1).fixedSize()
                        Spacer(minLength: 0)
                        BarLookPreview(event: previewEvent)
                    }
                }
                Section {
                    Toggle("終日", isOn: $allDay)
                    if allDay {
                        dayRow("開始日", $start)
                        dayRow("終了日", $end, from: start)
                    } else {
                        timeRow(.start)
                        timeRow(.end)
                        endNotationHints
                    }
                }
                // 共有カレンダーの中で作った予定だけ、メモ・画像・URL を付けられる(自分の予定を共有に出したものは、メモなどを共有しない)
                if target.event.isCalendarOwned {
                    AttachmentFields(memo: $memo, url: $url, imageId: $imageId, outsideTap: outsideTap, session: attachments,
                                     calendarId: attachmentCalendarId)
                }
                if failed {
                    Section { Text("保存できませんでした。通信を確認してください。").foregroundStyle(.red) }
                }
                // 最後に変えた人と時刻は、削除の見出しにして、行を取らないようにする
                if !target.isNew, flow?.isAtOrigin ?? true {
                    Section {
                        Button("削除", role: .destructive) { confirmDelete = true }
                    } header: {
                        LastModifiedHeader(line: target.event.lastModifiedText())
                    }
                }
            }
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .onDisappear { attachments.discardIfUncommitted() }
            .navigationTitle(target.isNew ? "共有カレンダーに追加" : "共有の予定を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(target.isNew ? "追加" : "保存") {
                        Task {
                            saving = true
                            failed = false
                            let e = built()
                            // 保存先を変えたときは、その共有カレンダーに新しく保存する(開いているカレンダーとは限らない)
                            let ok: Bool
                            if let flow, !flow.isAtOrigin, let cid = flow.destination {
                                ok = await shared.save(e, inCalendar: cid)
                            } else {
                                ok = await shared.save(e)
                            }
                            if ok {
                                attachments.commit(keeping: e.imageId)
                                store.rememberColor(color)
                                dismiss()
                                flow?.saved(e.placed ? e.startDate : nil)
                            } else {
                                failed = true
                            }
                            saving = false
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .keyboardDismissBar { closeTimePanel() }
            .onChange(of: focusedField) { old, new in
                guard let old, old == .startTime || old == .endTime, openPanel == (old == .startTime ? .start : .end) else { return }
                if new != .startTime && new != .endTime { closeTimePanel() }
            }
            .onChange(of: start) { normalizeEnd() }
            .onChange(of: end) { validateEndEdit() }
            .onChange(of: startTime) { normalizeEnd() }
            .onChange(of: endTime) { validateEndEdit() }
            .onChange(of: hasDate) { normalizeEnd() }
            .onChange(of: allDay) { normalizeEnd() }
            .alert("この予定を削除しますか?", isPresented: $confirmDelete) {
                Button("キャンセル", role: .cancel) {}
                Button("削除", role: .destructive) {
                    Task {
                        if await shared.delete(id: target.event.id) {
                            // 付いていた画像も、保存先から消す
                            if let id = target.event.imageId { await AttachmentCloud.remove(id) }
                            dismiss()
                        } else {
                            failed = true
                        }
                    }
                }
            } message: {
                Text("参加者全員のカレンダーから消えます。")
            }
        }
        .presentationDetents([.large])
    }
}
