import SwiftUI

struct WorkplaceEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// nil なら新規
    let workplace: Workplace?

    @State private var name: String
    @State private var color: String
    @State private var wage: String
    @State private var transport: String
    @State private var bonus: [String]
    @State private var holidayBonus: String
    @State private var rules: [BreakRuleDraft]
    @State private var breakFromNight: Bool
    @State private var closingDay: Int
    @State private var paydayOn: Bool
    @State private var paydayDay: Int
    @State private var paydayOffset: Int
    @State private var confirmApply = false
    @FocusState private var focus: String?

    private static let dayLabels = ["日", "月", "火", "水", "木", "金", "土"]

    init(workplace: Workplace?) {
        self.workplace = workplace
        _name = State(initialValue: workplace?.name ?? "")
        _color = State(initialValue: workplace?.color ?? Store.defaultColors[0])
        _wage = State(initialValue: Self.text(workplace?.hourlyWage))
        _transport = State(initialValue: Self.text(workplace?.transport))
        let b = workplace?.weekdayBonus ?? []
        _bonus = State(initialValue: (0..<7).map { Self.text($0 < b.count ? b[$0] : 0) })
        _holidayBonus = State(initialValue: Self.text(workplace?.holidayBonus))
        _rules = State(initialValue: (workplace?.breakRules ?? []).map { BreakRuleDraft(rule: $0) })
        _breakFromNight = State(initialValue: workplace?.breakFromNight ?? true)
        _closingDay = State(initialValue: workplace?.closingDay ?? 0)
        _paydayOn = State(initialValue: workplace?.paydayDay != nil)
        _paydayDay = State(initialValue: workplace?.paydayDay ?? 25)
        _paydayOffset = State(initialValue: workplace?.paydayMonthOffset ?? 1)
    }

    private static func text(_ v: Int?) -> String {
        guard let v, v > 0 else { return "" }
        return String(v)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var affectedCount: Int {
        guard let workplace else { return 0 }
        return store.eventCount(matchingTitle: workplace.name)
    }
    private var changed: Bool {
        guard let workplace else { return false }
        return trimmed != workplace.name || color != workplace.color
    }

    /// 数字だけを受け付ける(負数・小数なし)
    private func digits(_ text: Binding<String>) -> Binding<String> {
        Binding(
            get: { text.wrappedValue },
            set: { text.wrappedValue = String($0.filter { $0.isASCII && $0.isNumber }.prefix(7)) }
        )
    }

    private func moneyRow(_ label: String, _ text: Binding<String>, key: String, unit: String = "円") -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: digits(text))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
                .focused($focus, equals: key)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var dayOptions: some View {
        Text("末日").tag(0)
        ForEach(1...31, id: \.self) { d in
            Text("\(d)日").tag(d)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("職場の名前", text: $name)
                        .focused($focus, equals: "name")
                }
                Section("色") {
                    HStack(spacing: 10) {
                        ForEach(Store.defaultColors, id: \.self) { c in
                            ColorDot(hex: c, size: 24)
                                .overlay(Circle().stroke(Color.primary, lineWidth: color == c ? 2 : 0).padding(-3))
                                .onTapGesture { color = c }
                        }
                    }
                    ColorPicker("カスタム色",
                                selection: Binding(get: { Color(hex: color) }, set: { color = $0.toHex() }),
                                supportsOpacity: false)
                }
                Section("給与") {
                    moneyRow("時給", $wage, key: "wage")
                    moneyRow("交通費(片道)", $transport, key: "transport")
                    Text("1予定ごとに往復(×2)で計算します")
                        .font(.app(12))
                        .foregroundStyle(.secondary)
                }
                Section("曜日別の加給(円/時)") {
                    ForEach(0..<7, id: \.self) { i in
                        moneyRow(Self.dayLabels[i] + "曜日", $bonus[i], key: "bonus\(i)", unit: "円/時")
                    }
                }
                Section("祝日の加給") {
                    moneyRow("祝日", $holidayBonus, key: "holiday", unit: "円/時")
                }
                Section {
                    ForEach($rules) { $rule in
                        BreakRuleRow(rule: $rule, focus: $focus) {
                            rules.removeAll { $0.id == rule.id }
                        }
                    }
                    .onDelete { rules.remove(atOffsets: $0) }
                    Button("＋ 休憩ルールを追加") {
                        rules.append(BreakRuleDraft())
                    }
                    if rules.isEmpty {
                        Text("設定がなければ法定(6時間超45分、8時間超60分)")
                            .font(.app(12))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("休憩ルール")
                }
                Section {
                    Picker("締め日", selection: $closingDay) {
                        dayOptions
                    }
                    .pickerStyle(.menu)
                    Toggle("給料日を設定する", isOn: $paydayOn)
                    if paydayOn {
                        Picker("支払い月", selection: $paydayOffset) {
                            Text("当月").tag(0)
                            Text("翌月").tag(1)
                            Text("翌々月").tag(2)
                        }
                        .pickerStyle(.menu)
                        Picker("給料日", selection: $paydayDay) {
                            dayOptions
                        }
                        .pickerStyle(.menu)
                    }
                    Text("例: 末日締め・翌月25日払い")
                        .font(.app(12))
                        .foregroundStyle(.secondary)
                } header: {
                    Text("給料日")
                }
                Section("休憩を引く時間帯の既定") {
                    Picker("休憩を引く時間帯", selection: $breakFromNight) {
                        Text("深夜帯から引く").tag(true)
                        Text("深夜帯以外から引く").tag(false)
                    }
                    .pickerStyle(.menu)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(workplace == nil ? "職場を追加" : "職場を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(trimmed.isEmpty)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") { focus = nil }
                }
            }
            .confirmationDialog(
                "タイトルが『\(workplace?.name ?? "")』の予定 \(affectedCount) 件にも変更を反映しますか?",
                isPresented: $confirmApply, titleVisibility: .visible
            ) {
                Button("反映する") { commit(applyToEvents: true) }
                Button("この職場だけ変更") { commit(applyToEvents: false) }
                Button("キャンセル", role: .cancel) {}
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        focus = nil
        if workplace != nil, changed, affectedCount >= 1 {
            confirmApply = true
        } else {
            commit(applyToEvents: false)
        }
    }

    private func built(id: String) -> Workplace {
        Workplace(id: id, name: trimmed, color: color,
                  hourlyWage: Int(wage) ?? 0,
                  transport: Int(transport) ?? 0,
                  weekdayBonus: bonus.map { Int($0) ?? 0 },
                  holidayBonus: Int(holidayBonus) ?? 0,
                  breakRules: BreakRuleDraft.clean(rules),
                  breakFromNight: breakFromNight,
                  closingDay: closingDay,
                  paydayDay: paydayOn ? paydayDay : nil,
                  paydayMonthOffset: paydayOffset)
    }

    private func commit(applyToEvents: Bool) {
        if let workplace {
            store.updateWorkplace(id: workplace.id, name: trimmed, color: color, applyToEvents: applyToEvents)
            store.updateWorkplaceDetails(built(id: workplace.id))
        } else {
            store.addWorkplace(built(id: UUID().uuidString))
        }
        dismiss()
    }
}

private struct BreakRuleRow: View {
    @Binding var rule: BreakRuleDraft
    var focus: FocusState<String?>.Binding
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            TextField("00", text: Binding(
                get: { rule.hours },
                set: { input in
                    var seenDot = false
                    let cleaned = input.filter { ch in
                        if ch == "." && !seenDot { seenDot = true; return true }
                        return ch.isASCII && ch.isNumber
                    }
                    rule.hours = String(cleaned.prefix(5))
                }))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
                .focused(focus, equals: "rule-h-" + rule.id)
            Text("時間")
            Picker("条件", selection: $rule.comparison) {
                Text("以上").tag(BreakComparison.atLeast)
                Text("を超える").tag(BreakComparison.over)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            Spacer(minLength: 0)
            TextField("00", text: Binding(
                get: { rule.minutes },
                set: { input in
                    rule.minutes = String(input.filter { $0.isASCII && $0.isNumber }.prefix(3))
                }))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 40)
                .focused(focus, equals: "rule-m-" + rule.id)
            Text("分")
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }
}
