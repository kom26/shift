import SwiftUI
import UIKit

struct EventEditor: View {
    @Environment(Store.self) private var store
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
    @FocusState private var focusedField: Field?

    enum Field: Hashable { case title, memo, breakMinutes, startTime, endTime }

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
        _breakText = State(initialValue: Rules.breakOverride(of: original).map(String.init) ?? "")
    }

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }
    private var total: Int? { allDay ? nil : Rules.totalMinutes(start: startTime, end: endTime) }
    private var defaultBreak: Int { total.map { Rules.defaultBreak($0) } ?? 0 }
    private var hours: Double? {
        Rules.workHours(start: startTime, end: endTime, allDay: allDay, breakMinutes: Int(breakText))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("タイトル", text: $title)
                        .focused($focusedField, equals: .title)
                    if !store.workplaces.isEmpty { workplaceChips }
                    ColorRow(color: $color, recent: store.customColors)
                }
                Section {
                    Toggle("日付を指定", isOn: $hasDate)
                    if hasDate {
                        DatePicker("開始日", selection: $start, displayedComponents: .date)
                        DatePicker("終了日", selection: $end, in: start..., displayedComponents: .date)
                    }
                    Toggle("終日", isOn: $allDay)
                    if !allDay { timeRows }
                }
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
                    Button("完了") { focusedField = nil }
                }
            }
            .onChange(of: start) { _, new in if end < new { end = new } }
            .onChange(of: startTime) { breakText = "" }
            .onChange(of: endTime) { breakText = "" }
            .confirmationDialog("この予定を削除しますか?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    store.delete(id: original.id)
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var workplaceChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.workplaces) { w in
                    Button {
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
                        .overlay(Capsule().stroke(Theme.accent, lineWidth: title == w.name ? 2 : 0))
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var timeRows: some View {
        HStack(spacing: 16) {
            TimeColumn(label: "開始", value: $startTime, allow24: false, field: .startTime, focus: $focusedField)
            TimeColumn(label: "終了", value: $endTime, allow24: true, field: .endTime, focus: $focusedField)
        }
        if endTime <= startTime {
            Label("翌日またぎ → 終了日を自動で翌日にします", systemImage: "moon.stars")
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
        if let hours {
            LabeledContent("実労働", value: Rules.formatHours(hours))
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
        e.workHours = Rules.workHours(start: st, end: et, allDay: allDay, breakMinutes: Int(breakText))
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

private struct TimeColumn: View {
    let label: String
    @Binding var value: String
    let allow24: Bool
    let field: EventEditor.Field
    var focus: FocusState<EventEditor.Field?>.Binding

    @State private var draft = ""

    private var isFocused: Bool { focus.wrappedValue == field }

    private var items: [String] {
        var list = Rules.timeOptions15(allow24: allow24)
        if !list.contains(value) {
            let idx = list.firstIndex { $0 > value } ?? list.endIndex
            list.insert(value, at: idx)
        }
        return list
    }

    private var fieldText: Binding<String> {
        Binding(
            get: { isFocused ? draft : value },
            set: { input in
                guard isFocused else { return }
                let digits = String(input.filter { $0.isASCII && $0.isNumber }.prefix(4))
                draft = digits
                if digits.count == 4, let t = Rules.parseTimeDigits(digits, allow24: allow24) {
                    value = t
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.footnote).foregroundStyle(.secondary)
            TextField("", text: fieldText, prompt: Text(value))
                .keyboardType(.numberPad)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .focused(focus, equals: field)
            Picker(label, selection: $value) {
                ForEach(items, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(height: 110)
            .labelsHidden()
        }
        .frame(maxWidth: .infinity)
        .onChange(of: focus.wrappedValue) { old, new in
            // フォーカスの出入りで入力途中の文字を破棄(確定済みの値は value に反映済み)
            if old == field || new == field { draft = "" }
        }
    }
}
