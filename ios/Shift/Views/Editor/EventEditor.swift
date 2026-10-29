import SwiftUI
import UIKit

struct EventEditor: View {
    @Environment(Store.self) private var store
    @Environment(Holidays.self) private var holidays
    @Environment(\.dismiss) private var dismiss

    let original: ShiftEvent
    let isNew: Bool
    /// よく使う予定のテンプレートを編集する(日付なし。保存先はよく使う予定)
    var favoriteMode = false

    @State private var title: String
    @State private var memo: String
    @State private var color: String
    @State private var start: Date
    @State private var end: Date
    @State private var allDay: Bool
    @State private var startTime: String
    @State private var endTime: String
    @State private var breakText: String
    @State private var hasDate: Bool
    @State private var confirmDelete = false
    @State private var openPanel: TimePanel?
    @State private var shiftOpen = false
    @State private var registerFavorite = false
    @State private var typed = ""
    @State private var workplaceId: String?
    @State private var breakInNight: Bool?
    @State private var barShowsTitle: Bool
    @State private var didSetup = false
    @State private var lastValidEndDate: Date
    @State private var lastValidEndTime: String
    @State private var endWarningVisible = false
    @State private var endWarningTask: Task<Void, Never>?
    @State private var addingWorkplace = false
    @State private var workplaceCountBeforeAdd = 0
    @FocusState private var focusedField: Field?

    enum Field: Hashable { case title, memo, breakMinutes, startTime, endTime }
    enum TimePanel: Hashable { case start, end }

    init(original: ShiftEvent, isNew: Bool, favoriteMode: Bool = false) {
        self.original = original
        self.isNew = isNew
        self.favoriteMode = favoriteMode
        _title = State(initialValue: original.title)
        _memo = State(initialValue: original.memo)
        _color = State(initialValue: original.color)
        _start = State(initialValue: Rules.parse(original.startDate ?? "") ?? Date())
        let initialEnd = Rules.parse(original.endDate ?? original.startDate ?? "") ?? Date()
        _end = State(initialValue: initialEnd)
        _lastValidEndDate = State(initialValue: initialEnd)
        _hasDate = State(initialValue: original.startDate != nil)
        _allDay = State(initialValue: original.allDay)
        _startTime = State(initialValue: original.startTime ?? "09:00")
        _endTime = State(initialValue: original.endTime ?? "18:00")
        _lastValidEndTime = State(initialValue: original.endTime ?? "18:00")
        _workplaceId = State(initialValue: original.workplaceId)
        _breakInNight = State(initialValue: original.breakInNight)
        _barShowsTitle = State(initialValue: original.barShowsTitle ?? false)
        // 保存済みの休憩分(既定と同じ値は onAppear で空に戻す)
        let savedBreak: String
        if let wh = original.workHours, !original.allDay,
           let span = Rules.spanMinutes(startDate: original.startDate, startTime: original.startTime,
                                        endDate: original.endDate, endTime: original.endTime) {
            savedBreak = String(max(0, Int((Double(span) - wh * 60).rounded())))
        } else {
            savedBreak = ""
        }
        _breakText = State(initialValue: savedBreak)
    }

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }
    private var startDateText: String? { hasDate ? Rules.format(start) : nil }
    private var endDateText: String? { hasDate ? Rules.format(end) : nil }
    private var total: Int? {
        allDay ? nil : Rules.spanMinutes(startDate: startDateText, startTime: startTime,
                                         endDate: endDateText, endTime: endTime)
    }
    private var selectedWorkplace: Workplace? {
        guard let id = workplaceId else { return nil }
        return store.workplaces.first { $0.id == id }
    }
    private var defaultBreak: Int {
        total.map { BreakRules.minutes(span: $0, rules: selectedWorkplace?.breakRules ?? []) } ?? 0
    }
    private var effectiveBreak: Int { Int(breakText) ?? defaultBreak }
    private var hours: Double? {
        Rules.workHours(startDate: startDateText, startTime: startTime, endDate: endDateText, endTime: endTime,
                        allDay: allDay, breakMinutes: effectiveBreak)
    }
    private var showsNightPicker: Bool {
        !allDay && effectiveBreak >= 1
            && PayCalculator.nightMinutes(startDate: startDateText, startTime: startTime,
                                          endDate: endDateText, endTime: endTime) > 0
    }
    private var breakInNightNoWorkplace: Binding<Bool> {
        Binding(get: { breakInNight ?? true }, set: { breakInNight = $0 })
    }
    private var payBreakdown: PayBreakdown? {
        guard let w = selectedWorkplace, !allDay else { return nil }
        let holiday = hasDate && holidays.name(on: Rules.format(start)) != nil
        return PayCalculator.pay(event: build(), workplace: w, isHoliday: holiday)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                Section {
                    workplaceChips
                    TextField("タイトル(必須)", text: $title)
                        .focused($focusedField, equals: .title)
                    ColorRow(color: $color, recent: store.customColors, onDeleteRecent: { store.removeCustomColor($0) })
                }
                Section {
                    Toggle("終日", isOn: $allDay)
                    if allDay {
                        HStack(spacing: 8) {
                            Text("開始日")
                            Spacer()
                            startDateControl
                        }
                        HStack(spacing: 8) {
                            Text("終了日")
                            Spacer()
                            endDateControl
                        }
                    } else {
                        timeRows
                        Picker("バーの表示", selection: $barShowsTitle) {
                            Text("時間").tag(false)
                            Text("予定名").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                if let p = payBreakdown { paySection(p) }
                Section {
                    TextField("メモ(任意)", text: $memo, axis: .vertical).lineLimit(2...5)
                        .focused($focusedField, equals: .memo)
                }
                if !favoriteMode {
                    Section {
                        Toggle("よく使う予定にも登録", isOn: $registerFavorite)
                    }
                }
                Section {
                    if !favoriteMode {
                        Button("複製保存") { commit(duplicate: true) }.disabled(!canSave)
                    }
                    if !isNew {
                        Button("削除", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: openPanel) { _, new in
                guard let new else { return }
                scrollToPanelBottom(new, proxy: proxy)
            }
            }
            .navigationTitle(favoriteMode ? (isNew ? "よく使う予定を追加" : "よく使う予定を編集") : (isNew ? "予定を追加" : "予定を編集"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "追加" : "保存") { commit(duplicate: false) }.disabled(!canSave)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("確定") { closeTimePanel() }
                }
            }
            .onAppear {
                guard !didSetup else { return }
                didSetup = true
                registerFavorite = !favoriteMode && store.isFavorite(original)
                if selectedWorkplace == nil {
                    workplaceId = store.workplace(for: original)?.id
                }
                if let b = Int(breakText), b == defaultBreak { breakText = "" }
            }
            .onChange(of: focusedField) { old, new in
                guard let old, let oldPanel = panel(for: old), openPanel == oldPanel else { return }
                if new == nil || panel(for: new!) == nil { closeTimePanel() }
            }
            .onChange(of: start) { normalizeEnd() }
            .onChange(of: end) { validateEndEdit() }
            .onChange(of: startTime) { breakText = ""; normalizeEnd() }
            .onChange(of: endTime) { validateEndEdit() }
            .onChange(of: hasDate) { normalizeEnd() }
            .onChange(of: allDay) { normalizeEnd() }
            .confirmationDialog("この予定を削除しますか?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    if favoriteMode { store.removeFavorite(id: original.id) } else { store.delete(id: original.id) }
                    dismiss()
                }
            }
        }
        .presentationDetents([.large])
        .sheet(isPresented: $addingWorkplace, onDismiss: selectNewWorkplace) {
            WorkplaceEditor(workplace: nil)
        }
    }

    private func selectNewWorkplace() {
        guard store.workplaces.count > workplaceCountBeforeAdd, let w = store.workplaces.last else { return }
        workplaceId = w.id
        title = w.name
        color = w.color
    }

    private var workplaceChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    workplaceId = nil
                    title = ""
                    color = Store.defaultColors[0]
                } label: {
                    Text("通常予定").font(.app(13)).foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(.secondarySystemFill)))
                        .overlay(Capsule().stroke(Theme.accent, lineWidth: selectedWorkplace == nil ? 2 : 0))
                }
                .buttonStyle(.borderless)
                ForEach(store.workplaces) { w in
                    Button {
                        workplaceId = w.id
                        title = w.name
                        color = w.color
                    } label: {
                        HStack(spacing: 6) {
                            ColorDot(hex: w.color, size: 10)
                            Text(w.name).font(.app(13)).foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(.secondarySystemFill)))
                        .overlay(Capsule().stroke(Theme.accent, lineWidth: selectedWorkplace?.id == w.id ? 2 : 0))
                    }
                    .buttonStyle(.borderless)
                }
                Button {
                    workplaceCountBeforeAdd = store.workplaces.count
                    addingWorkplace = true
                } label: {
                    Image(systemName: "plus").font(.footnote).foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .overlay(Capsule().strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("職場を追加")
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
        }
    }

    // MARK: 時刻入力

    private func maxMinutes(_ p: TimePanel) -> Int { p == .start ? Rules.maxStartMinutes : Rules.maxEndMinutes }
    private func timeValue(_ p: TimePanel) -> String { p == .start ? startTime : endTime }

    private func setTime(_ p: TimePanel, _ t: String) {
        if p == .start { startTime = t } else { endTime = t }
        typed = Self.digits(of: t)
    }

    private static func digits(of time: String) -> String { time.filter { $0.isASCII && $0.isNumber } }

    private func closeTimePanel() {
        typed = ""
        focusedField = nil
        withAnimation(.easeInOut(duration: 0.2)) { openPanel = nil }
    }

    private func toggleTimePanel(_ p: TimePanel) {
        shiftOpen = false
        let next: TimePanel? = openPanel == p ? nil : p
        typed = next == nil ? "" : Self.digits(of: timeValue(p))
        withAnimation(.easeInOut(duration: 0.2)) { openPanel = next }
        focusedField = next.map(field(for:))
    }

    private func field(for p: TimePanel) -> Field { p == .start ? .startTime : .endTime }

    private func panel(for f: Field) -> TimePanel? {
        switch f {
        case .startTime: return .start
        case .endTime: return .end
        default: return nil
        }
    }

    private func panelBottomId(_ p: TimePanel) -> String { p == .start ? "startPanelBottom" : "endPanelBottom" }

    /// パネル下端が見えるようスクロール(キーボード表示後にもう一度)
    private func scrollToPanelBottom(_ p: TimePanel, proxy: ScrollViewProxy) {
        let id = panelBottomId(p)
        withAnimation { proxy.scrollTo(id, anchor: .bottom) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard openPanel == p else { return }
            withAnimation { proxy.scrollTo(id, anchor: .bottom) }
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

    private func datePlaceholderChip(enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("日付未定")
                .font(.app(17))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemFill)))
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    @ViewBuilder
    private var startDateControl: some View {
        if favoriteMode {
            EmptyView()
        } else if hasDate {
            DatePicker("", selection: $start, displayedComponents: .date).labelsHidden()
        } else {
            datePlaceholderChip(enabled: true) {
                let d = Rules.parse(Rules.today()) ?? Date()
                lastValidEndDate = d
                start = d
                end = d
                hasDate = true
            }
        }
    }

    @ViewBuilder
    private var endDateControl: some View {
        if favoriteMode {
            EmptyView()
        } else if hasDate {
            DatePicker("", selection: $end, in: start..., displayedComponents: .date).labelsHidden()
        } else {
            datePlaceholderChip(enabled: false) {}
        }
    }

    @ViewBuilder
    private func timeRow(_ p: TimePanel) -> some View {
        HStack(spacing: 8) {
            Text(p == .start ? "開始" : "終了")
            Spacer()
            if p == .start { startDateControl } else { endDateControl }
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
                // キーボードが閉じてもパネルを閉じられるよう、確定ボタンをパネルの右上に置く
                HStack {
                    Spacer()
                    Button("確定") { closeTimePanel() }
                        .font(.app(15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .buttonStyle(.plain)
                        .padding(.vertical, 6)
                }
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
        .compositingGroup()
        .clipped()
    }

    @ViewBuilder
    private var timeRows: some View {
        timeRow(.start)
        timeRow(.end)
        endNotationHints
        // 通常予定(職場なし)には休憩・シフト時間・実労働は出さない
        if selectedWorkplace != nil { workRows }
    }

    @ViewBuilder
    private var workRows: some View {
        HStack {
            Text("休憩")
            Spacer()
            TextField("\(defaultBreak)", text: $breakText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
                .focused($focusedField, equals: .breakMinutes)
            Text("分")
            if !breakText.isEmpty && breakText != String(defaultBreak) {
                Button("リセット") { breakText = "" }
                    .font(.app(13))
                    .buttonStyle(.borderless)
            }
        }
        if showsNightPicker {
            if let w = selectedWorkplace {
                Picker("休憩を引く時間帯", selection: $breakInNight) {
                    Text("職場設定に従う").tag(Bool?.none)
                    Text("深夜帯から").tag(Bool?.some(true))
                    Text("深夜帯以外から").tag(Bool?.some(false))
                }
                .pickerStyle(.menu)
            } else {
                Picker("休憩を引く時間帯", selection: breakInNightNoWorkplace) {
                    Text("深夜帯から").tag(true)
                    Text("深夜帯以外から").tag(false)
                }
                .pickerStyle(.menu)
            }
        }
        if let total { shiftDurationRow(total) }
        if let hours {
            LabeledContent("実労働", value: Rules.formatHours(hours))
        }
    }

    // MARK: 終了の表記切り替え

    private var endDaysFromStart: Int {
        hasDate ? Rules.daysBetween(Rules.format(start), Rules.format(end)) : 1
    }

    /// 終了を一括で置き換える。lastValid を先に揃えて、終了の検証(validateEndEdit)を発火させない
    private func applyEnd(date: Date, time: String) {
        lastValidEndDate = date
        lastValidEndTime = time
        end = date
        endTime = time
        breakText = ""
    }

    @ViewBuilder
    private var endNotationHints: some View {
        if let sm = Rules.minutes(startTime), let em = Rules.minutes(endTime) {
            if em <= sm, em < 1440, endDaysFromStart == 1, let ext = Rules.extendedEndText(endTime) {
                notationHint("\(ext)とすると同日の予定として表記") {
                    applyEnd(date: start, time: ext)
                }
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

    // MARK: シフト時間

    private func shiftText(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60)時間" : "\(minutes / 60)時間\(minutes % 60)分"
    }

    /// 開始は動かさず、終了(日付と時刻)をシフト時間に合わせる
    private func setShiftMinutes(_ dur: Int) {
        guard let sm = Rules.minutes(startTime) else { return }
        let abs = sm + dur
        let time = String(format: "%02d:%02d", (abs % 1440) / 60, abs % 60)
        let date = hasDate ? (Rules.parse(Rules.addDays(Rules.format(start), abs / 1440)) ?? end) : end
        applyEnd(date: date, time: time)
    }

    @ViewBuilder
    private func shiftDurationRow(_ total: Int) -> some View {
        HStack(spacing: 8) {
            Text("シフト時間")
            Spacer()
            Button {
                if shiftOpen {
                    shiftOpen = false
                } else {
                    closeTimePanel()
                    shiftOpen = true
                }
            } label: {
                Text(shiftText(total))
                    .font(.app(17).monospacedDigit())
                    .foregroundStyle(shiftOpen ? Theme.onAccent : Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(shiftOpen ? Theme.accent : Color(.secondarySystemFill)))
            }
            .buttonStyle(.borderless)
        }
        if shiftOpen {
            HStack {
                Spacer()
                Button("確定") { shiftOpen = false }
                    .font(.app(15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
            }
            shiftWheel(total)
        }
    }

    private func shiftWheel(_ total: Int) -> some View {
        let h = min(total / 60, 48), m = total % 60
        var minuteItems = Rules.minuteOptions
        if !minuteItems.contains(m) { minuteItems.append(m); minuteItems.sort() }
        let hourBinding = Binding<Int>(get: { h }, set: { setShiftMinutes($0 * 60 + m) })
        let minuteBinding = Binding<Int>(get: { m }, set: { setShiftMinutes(h * 60 + $0) })
        return HStack(spacing: 0) {
            Picker("時間", selection: hourBinding) {
                ForEach(0...48, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            Text("時間").font(.app(15))
            Picker("分", selection: minuteBinding) {
                ForEach(minuteItems, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            Text("分").font(.app(15))
        }
        .frame(height: 140)
        .compositingGroup()
        .clipped()
    }

    private func paySection(_ p: PayBreakdown) -> some View {
        Section {
            HStack {
                Text("見込み給与")
                Spacer()
                Text(Money.yen(p.total)).font(.app(20, weight: .bold).monospacedDigit())
            }
            payRow("基本", p.base, always: true)
            payRow("深夜割増", p.night)
            payRow("残業割増", p.overtime)
            payRow("加給", p.bonus)
            payRow("交通費(往復)", p.transport)
            LabeledContent("実労働", value: Rules.formatHours(Double(p.netMinutes) / 60))
                .font(.app(13))
        }
    }

    @ViewBuilder
    private func payRow(_ label: String, _ amount: Double, always: Bool = false) -> some View {
        if always || amount > 0 {
            LabeledContent(label, value: Money.yen(amount))
                .font(.app(13))
        }
    }

    /// 開始側の編集で終了が開始より前になったら終了日を進める(終日は 終了日 >= 開始日)。
    /// 終了側の最後の有効値も更新するので、終了の検証(validateEndEdit)は何もしない
    private func normalizeEnd() {
        guard hasDate else { return }
        if allDay {
            if end < start { end = start }
            syncLastValidEnd()
            return
        }
        let next = Rules.normalizedEndDate(
            startDate: Rules.format(start), startTime: startTime,
            endDate: Rules.format(end), endTime: endTime)
        if next != Rules.format(end), let d = Rules.parse(next) {
            lastValidEndDate = d
            lastValidEndTime = endTime
            end = d
        } else {
            syncLastValidEnd()
        }
    }

    private func syncLastValidEnd() {
        lastValidEndDate = end
        lastValidEndTime = endTime
    }

    /// 終了側の編集の検証。
    /// 終了時刻の編集: 開始より前になるなら通知なしで終了日を進める。
    /// 終了日の編集: 開始より前になるなら直前の日付へ戻して警告する。
    /// いずれも lastValid を先に更新/一致させるため、再度のonChangeでは何もしない(ループしない)
    private func validateEndEdit() {
        guard hasDate, !allDay else { syncLastValidEnd(); return }
        let dateChanged = Rules.format(end) != Rules.format(lastValidEndDate)
        let timeChanged = endTime != lastValidEndTime
        guard dateChanged || timeChanged else { return }
        if timeChanged {
            breakText = ""
            let next = Rules.normalizedEndDate(
                startDate: Rules.format(start), startTime: startTime,
                endDate: Rules.format(end), endTime: endTime)
            if next != Rules.format(end), let d = Rules.parse(next) {
                lastValidEndDate = d
                lastValidEndTime = endTime
                end = d
            } else {
                syncLastValidEnd()
            }
        } else if Rules.isEndBeforeStart(
            startDate: Rules.format(start), startTime: startTime,
            endDate: Rules.format(end), endTime: endTime) {
            end = lastValidEndDate
            typed = ""
            showEndWarning()
        } else {
            syncLastValidEnd()
        }
    }

    private func showEndWarning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        endWarningTask?.cancel()
        withAnimation { endWarningVisible = true }
        endWarningTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { endWarningVisible = false }
        }
    }

    private func build() -> ShiftEvent {
        var e = original
        let st = allDay ? nil : startTime
        let et = allDay ? nil : endTime
        let sd = Rules.format(start)
        e.title = title.trimmingCharacters(in: .whitespaces)
        e.memo = memo
        e.color = color
        if hasDate {
            e.startDate = sd
            e.endDate = Rules.resolveEndDate(start: sd, end: Rules.format(end), allDay: allDay, startTime: st, endTime: et)
            e.placed = true
        } else {
            e.startDate = nil
            e.endDate = nil
            e.placed = false
        }
        e.allDay = allDay
        e.startTime = st
        e.endTime = et
        e.workHours = Rules.workHours(startDate: e.startDate, startTime: st, endDate: e.endDate, endTime: et,
                                      allDay: allDay, breakMinutes: effectiveBreak)
        e.workplaceId = workplaceId
        e.breakInNight = breakInNight
        e.barShowsTitle = barShowsTitle ? true : nil
        return e
    }

    private func commit(duplicate: Bool) {
        let e = build()
        store.rememberColor(e.color)
        if favoriteMode {
            store.saveFavorite(e)
        } else {
            if duplicate { store.saveAndDuplicate(e) } else { store.save(e) }
            if registerFavorite && !store.isFavorite(e) { store.addFavorite(from: e) }
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dismiss()
    }
}

private struct ColorRow: View {
    @Binding var color: String
    let recent: [String]
    var onDeleteRecent: (String) -> Void = { _ in }
    /// 最近の色でタップした色。右にゴミ箱を出す
    @State private var trashColor: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            swatches(Store.defaultColors)
            if !recent.isEmpty {
                HStack {
                    Text("最近").font(.app(11)).foregroundStyle(.secondary)
                    swatches(recent, isRecent: true)
                    if let t = trashColor, recent.contains(t) {
                        Button {
                            onDeleteRecent(t)
                            trashColor = nil
                        } label: {
                            Image(systemName: "trash")
                                .font(.app(15))
                                .foregroundStyle(Theme.deltaDown)
                                .padding(6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("この色を削除")
                    }
                }
            }
            ColorPicker("カスタム色",
                        selection: EventColor.pickerBinding($color),
                        supportsOpacity: false)
        }
    }

    private func swatches(_ list: [String], isRecent: Bool = false) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(list, id: \.self) { c in
                ColorDot(hex: c, size: 24)
                    .overlay(Circle().stroke(Color.primary, lineWidth: color == c ? 2 : 0).padding(-3))
                    .onTapGesture {
                        color = c
                        trashColor = isRecent ? c : nil
                    }
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 5)
        }
    }
}
