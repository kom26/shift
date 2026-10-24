import SwiftUI
import UIKit

struct EventEditor: View {
    @Environment(Store.self) private var store
    @Environment(Holidays.self) private var holidays
    @Environment(\.dismiss) private var dismiss

    let original: ShiftEvent
    let isNew: Bool

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
    @State private var typed = ""
    @State private var workplaceId: String?
    @State private var breakInNight: Bool?
    @State private var didSetup = false
    @State private var addingWorkplace = false
    @State private var workplaceCountBeforeAdd = 0
    @FocusState private var focusedField: Field?

    enum Field: Hashable { case title, memo, breakMinutes, timeEntry }
    enum TimePanel: Hashable { case start, end }

    init(original: ShiftEvent, isNew: Bool) {
        self.original = original
        self.isNew = isNew
        _title = State(initialValue: original.title)
        _memo = State(initialValue: original.memo)
        _color = State(initialValue: original.color)
        _start = State(initialValue: Rules.parse(original.startDate ?? "") ?? Date())
        _end = State(initialValue: Rules.parse(original.endDate ?? original.startDate ?? "") ?? Date())
        _hasDate = State(initialValue: original.startDate != nil)
        _allDay = State(initialValue: original.allDay)
        _startTime = State(initialValue: original.startTime ?? "09:00")
        _endTime = State(initialValue: original.endTime ?? "18:00")
        _workplaceId = State(initialValue: original.workplaceId)
        _breakInNight = State(initialValue: original.breakInNight)
        // 保存済みの休憩分(既定と同じ値は onAppear で空に戻す)
        let savedBreak: String
        if let wh = original.workHours, !original.allDay,
           let span = Rules.totalMinutes(start: original.startTime, end: original.endTime) {
            savedBreak = String(max(0, Int((Double(span) - wh * 60).rounded())))
        } else {
            savedBreak = ""
        }
        _breakText = State(initialValue: savedBreak)
    }

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }
    private var total: Int? { allDay ? nil : Rules.totalMinutes(start: startTime, end: endTime) }
    private var selectedWorkplace: Workplace? {
        guard let id = workplaceId else { return nil }
        return store.workplaces.first { $0.id == id }
    }
    private var defaultBreak: Int {
        total.map { BreakRules.minutes(span: $0, rules: selectedWorkplace?.breakRules ?? []) } ?? 0
    }
    private var effectiveBreak: Int { Int(breakText) ?? defaultBreak }
    private var hours: Double? {
        Rules.workHours(start: startTime, end: endTime, allDay: allDay, breakMinutes: effectiveBreak)
    }
    private var showsNightPicker: Bool {
        !allDay && selectedWorkplace != nil && effectiveBreak >= 1
            && PayCalculator.nightMinutes(startTime: startTime, endTime: endTime) > 0
    }
    private var payBreakdown: PayBreakdown? {
        guard let w = selectedWorkplace, !allDay else { return nil }
        let holiday = hasDate && holidays.name(on: Rules.format(start)) != nil
        return PayCalculator.pay(event: build(), workplace: w, isHoliday: holiday)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("タイトル", text: $title)
                        .focused($focusedField, equals: .title)
                    workplaceChips
                    ColorRow(color: $color, recent: store.customColors)
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
                    }
                }
                if let p = payBreakdown { paySection(p) }
                Section {
                    TextField("メモ(任意)", text: $memo, axis: .vertical).lineLimit(2...5)
                        .focused($focusedField, equals: .memo)
                }
                Section {
                    Button("複製保存") { commit(duplicate: true) }.disabled(!canSave)
                    if !isNew {
                        Button("削除", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isNew ? "予定を追加" : "予定を編集")
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
                    Button("完了") { closeTimePanel() }
                }
            }
            .onAppear {
                guard !didSetup else { return }
                didSetup = true
                if selectedWorkplace == nil {
                    workplaceId = store.workplace(for: original)?.id
                }
                if let b = Int(breakText), b == defaultBreak { breakText = "" }
            }
            .onChange(of: focusedField) { old, new in
                if old == .timeEntry && new != .timeEntry && openPanel != nil { closeTimePanel() }
            }
            .onChange(of: start) { normalizeEnd() }
            .onChange(of: end) { normalizeEnd() }
            .onChange(of: startTime) { breakText = ""; normalizeEnd() }
            .onChange(of: endTime) { breakText = ""; normalizeEnd() }
            .onChange(of: hasDate) { normalizeEnd() }
            .onChange(of: allDay) { normalizeEnd() }
            .confirmationDialog("この予定を削除しますか?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    store.delete(id: original.id)
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
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
                } label: {
                    Text("指定なし").font(.footnote).foregroundStyle(.primary)
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
                            Circle().fill(Color(hex: w.color)).frame(width: 10, height: 10)
                            Text(w.name).font(.footnote).foregroundStyle(.primary)
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
            .padding(.vertical, 2)
        }
    }

    // MARK: 時刻入力

    private func maxMinutes(_ p: TimePanel) -> Int { p == .start ? Rules.maxStartMinutes : Rules.maxEndMinutes }
    private func timeValue(_ p: TimePanel) -> String { p == .start ? startTime : endTime }

    private func setTime(_ p: TimePanel, _ t: String) {
        if p == .start { startTime = t } else { endTime = t }
    }

    private func closeTimePanel() {
        typed = ""
        focusedField = nil
        withAnimation(.easeInOut(duration: 0.2)) { openPanel = nil }
    }

    private func toggleTimePanel(_ p: TimePanel) {
        typed = ""
        let next: TimePanel? = openPanel == p ? nil : p
        withAnimation(.easeInOut(duration: 0.2)) { openPanel = next }
        focusedField = next == nil ? nil : .timeEntry
    }

    /// チップの表示。入力途中なら打鍵中の数字を時刻の形で見せる
    private func chipText(_ p: TimePanel) -> String {
        guard openPanel == p, !typed.isEmpty else { return timeValue(p) }
        return typed.count <= 2 ? typed : String(typed.prefix(2)) + ":" + String(typed.dropFirst(2))
    }

    private var typedBinding: Binding<String> {
        Binding(
            get: { typed },
            set: { input in
                guard let p = openPanel else { return }
                let digits = String(input.filter { $0.isASCII && $0.isNumber }.prefix(4))
                if digits.count == 4 {
                    if let t = Rules.parseTimeDigits(digits, maxMinutes: maxMinutes(p)) {
                        setTime(p, t)
                    } else {
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                    }
                    typed = ""
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
                .font(.body.monospacedDigit())
                .foregroundStyle(open ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(open ? Theme.accent : Color(.secondarySystemFill)))
        }
        .buttonStyle(.borderless)
    }

    private func datePlaceholderChip(enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("日付未定")
                .font(.body)
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
        if hasDate {
            DatePicker("", selection: $start, displayedComponents: .date).labelsHidden()
        } else {
            datePlaceholderChip(enabled: true) {
                let d = Rules.parse(Rules.today()) ?? Date()
                start = d
                end = d
                hasDate = true
            }
        }
    }

    @ViewBuilder
    private var endDateControl: some View {
        if hasDate {
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
        if openPanel == p { wheelPanel(p) }
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
            Text(":").font(.title3.monospacedDigit())
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
            .overlay(alignment: .leading) {
                TextField("", text: typedBinding)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .timeEntry)
                    .frame(width: 1, height: 1)
                    .opacity(0.02)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        timeRow(.end)
        if let sm = Rules.minutes(startTime), let em = Rules.minutes(endTime), em <= sm, em < 1440,
           let ext = Rules.extendedEndText(endTime) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle")
                Text("\(ext)とすると同日の予定として表記")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
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
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }
        }
        if showsNightPicker {
            Picker("休憩を引く時間帯", selection: $breakInNight) {
                Text("職場の既定に従う").tag(Bool?.none)
                Text("深夜帯から").tag(Bool?.some(true))
                Text("深夜以外から").tag(Bool?.some(false))
            }
            .pickerStyle(.menu)
        }
        if let hours {
            LabeledContent("実労働", value: Rules.formatHours(hours))
        }
    }

    private func paySection(_ p: PayBreakdown) -> some View {
        Section {
            HStack {
                Text("見込み給与")
                Spacer()
                Text(Money.yen(p.total)).font(.title3.weight(.bold).monospacedDigit())
            }
            payRow("基本", p.base, always: true)
            payRow("深夜割増", p.night)
            payRow("残業割増", p.overtime)
            payRow("加給", p.bonus)
            payRow("交通費", p.transport)
            LabeledContent("実労働", value: Rules.formatHours(Double(p.netMinutes) / 60))
                .font(.footnote)
        }
    }

    @ViewBuilder
    private func payRow(_ label: String, _ amount: Double, always: Bool = false) -> some View {
        if always || amount > 0 {
            LabeledContent(label, value: Money.yen(amount))
                .font(.footnote)
        }
    }

    /// 終了が開始より前になったら終了日を進める(終日は 終了日 >= 開始日)
    private func normalizeEnd() {
        guard hasDate else { return }
        if allDay {
            if end < start { end = start }
            return
        }
        let next = Rules.normalizedEndDate(
            startDate: Rules.format(start), startTime: startTime,
            endDate: Rules.format(end), endTime: endTime)
        if next != Rules.format(end), let d = Rules.parse(next) { end = d }
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
        e.workHours = Rules.workHours(start: st, end: et, allDay: allDay, breakMinutes: effectiveBreak)
        e.workplaceId = workplaceId
        e.breakInNight = breakInNight
        return e
    }

    private func commit(duplicate: Bool) {
        let e = build()
        store.rememberColor(e.color)
        if duplicate { store.saveAndDuplicate(e) } else { store.save(e) }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dismiss()
    }
}

private struct ColorRow: View {
    @Binding var color: String
    let recent: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            swatches(Store.defaultColors)
            if !recent.isEmpty {
                HStack {
                    Text("最近").font(.caption2).foregroundStyle(.secondary)
                    swatches(recent)
                }
            }
            ColorPicker("カスタム色",
                        selection: Binding(get: { Color(hex: color) }, set: { color = $0.toHex() }),
                        supportsOpacity: false)
        }
    }

    private func swatches(_ list: [String]) -> some View {
        HStack(spacing: 10) {
            ForEach(list, id: \.self) { c in
                Circle()
                    .fill(Color(hex: c))
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color.primary, lineWidth: color == c ? 2 : 0).padding(-3))
                    .onTapGesture { color = c }
            }
        }
    }
}
