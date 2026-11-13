import SwiftUI

// 職場の設定画面から開くサブページ(曜日・祝日加給、休憩、給料日、給与の履歴)と、改定の追加・編集

/// 数字だけを受け付ける(負数・小数なし)
func digitsBinding(_ text: Binding<String>) -> Binding<String> {
    Binding(
        get: { text.wrappedValue },
        set: { text.wrappedValue = String($0.filter { $0.isASCII && $0.isNumber }.prefix(7)) }
    )
}

/// 金額 1 行(ラベル、右寄せの数字、単位)
struct MoneyRow: View {
    let label: String
    @Binding var text: String
    var unit: String = "円"
    var focus: FocusState<String?>.Binding
    let key: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: digitsBinding($text))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 100)
                .focused(focus, equals: key)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

/// 曜日別の加給を、1 行に 7 マスで入れる
struct BonusGrid: View {
    @Binding var bonus: [String]
    var focus: FocusState<String?>.Binding

    private static let dayLabels = ["日", "月", "火", "水", "木", "金", "土"]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                VStack(spacing: 4) {
                    Text(Self.dayLabels[i])
                        .font(.app(13))
                        .foregroundStyle(.secondary)
                    TextField("0", text: digitsBinding($bonus[i]))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.app(15).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
                        .focused(focus, equals: "bonus\(i)")
                        .accessibilityLabel("\(Self.dayLabels[i])曜日の加給")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 曜日・祝日加給

struct BonusPage: View {
    @Binding var bonus: [String]
    @Binding var holidayBonus: String
    @FocusState private var focus: String?

    var body: some View {
        Form {
            Section("曜日別の加給(円/時)") {
                BonusGrid(bonus: $bonus, focus: $focus)
            }
            Section {
                MoneyRow(label: "祝日", text: $holidayBonus, unit: "円/時", focus: $focus, key: "holiday")
            } header: {
                Text("祝日の加給")
            } footer: {
                Text("祝日は、曜日の加給のかわりにこちらを使います")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("曜日・祝日加給")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDismissBar { focus = nil }
    }
}

// MARK: - 休憩

struct BreakPage: View {
    @Binding var rules: [BreakRuleDraft]
    @Binding var breakFromNight: Bool
    @FocusState private var focus: String?

    var body: some View {
        Form {
            Section {
                ForEach($rules) { $rule in
                    BreakRuleRow(rule: $rule, focus: $focus) {
                        rules.removeAll { $0.id == rule.id }
                    }
                }
                .onDelete { rules.remove(atOffsets: $0) }
                Button("＋ 独自の休憩ルールを追加") {
                    rules.append(BreakRuleDraft())
                }
                if BreakRuleDraft.hasDuplicateThreshold(rules) {
                    Label("時間(しきい値)が同じルールがあります。一番下の行が使われます", systemImage: "exclamationmark.triangle")
                        .font(.app(12))
                        .foregroundStyle(Color.orange)
                }
            } header: {
                Text("独自の休憩ルール")
            } footer: {
                if rules.isEmpty {
                    Text("設定がなければ法定(6時間超45分、8時間超60分)")
                }
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
        .navigationTitle("休憩")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDismissBar { focus = nil }
    }
}

// MARK: - 給料日

struct PaydayPage: View {
    let isDaily: Bool
    @Binding var dailyMonthly: Bool
    @Binding var closingDay: Int
    @Binding var paydayOn: Bool
    @Binding var paydayDay: Int
    @Binding var paydayOffset: Int

    /// 締め日・給料日の設定を出すか(時給、または月払いの日給)
    private var usesCycle: Bool { !isDaily || dailyMonthly }

    @ViewBuilder
    private var dayOptions: some View {
        Text("末日").tag(0)
        ForEach(1...31, id: \.self) { d in
            Text("\(d)日").tag(d)
        }
    }

    var body: some View {
        Form {
            Section {
                if isDaily {
                    TwoWayPicker("支払い", selection: $dailyMonthly, first: ("日払い", false), second: ("月払い", true))
                }
                if usesCycle {
                    Picker("締め日", selection: $closingDay) { dayOptions }
                        .pickerStyle(.menu)
                    Toggle("給料日を設定する", isOn: $paydayOn)
                    if paydayOn {
                        Picker("支払い月", selection: $paydayOffset) {
                            Text("当月").tag(0)
                            Text("翌月").tag(1)
                            Text("翌々月").tag(2)
                        }
                        .pickerStyle(.menu)
                        Picker("給料日", selection: $paydayDay) { dayOptions }
                            .pickerStyle(.menu)
                    }
                }
            } footer: {
                if usesCycle {
                    Text("例: 末日締め・翌月25日払い")
                }
            }
        }
        .navigationTitle("給料日")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 給与の履歴

struct WageHistoryPage: View {
    @Binding var rates: [PayRate]
    let today: String

    @State private var editing: RateEditTarget?

    private var todayIndex: Int {
        rates.lastIndex(where: { $0.from <= today }) ?? 0
    }

    private func title(at i: Int) -> String {
        let r = rates[i]
        if !r.from.isEmpty { return WorkplaceSummary.date(r.from) + "から" }
        if rates.count > 1 { return "最初 〜 " + WorkplaceSummary.date(Rules.addDays(rates[1].from, -1)) }
        return "最初から"
    }

    private func detail(_ r: PayRate) -> String {
        var first = "時給 " + WorkplaceSummary.yen(r.hourlyWage)
        if r.transport > 0 { first += " ・ 交通費 " + WorkplaceSummary.yen(r.transport) }
        let bonus = WorkplaceSummary.bonus(weekday: r.weekdayBonus, holiday: r.holidayBonus)
        return bonus == "なし" ? first : first + "\n" + bonus
    }

    var body: some View {
        Form {
            Section {
                ForEach(Array(rates.indices.reversed()), id: \.self) { i in
                    Button {
                        editing = RateEditTarget(rate: rates[i], mode: .edit)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(title(at: i)).foregroundStyle(Color.primary)
                                    if i == todayIndex {
                                        Text("いま")
                                            .font(.app(11, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 7).padding(.vertical, 2)
                                            .background(Color.accentColor, in: Capsule())
                                    } else if rates[i].from > today {
                                        Text("これから")
                                            .font(.app(11, weight: .bold))
                                            .foregroundStyle(Color.accentColor)
                                            .padding(.horizontal, 7).padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                                    }
                                }
                                Text(detail(rates[i]))
                                    .font(.app(13).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.app(13, weight: .semibold))
                                .foregroundStyle(Color(.tertiaryLabel))
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if !rates[i].from.isEmpty {
                            Button("削除", role: .destructive) {
                                let id = rates[i].id
                                rates.removeAll { $0.id == id }
                            }
                        }
                    }
                }
            } footer: {
                Text("予定の給与は、その予定の開始日の設定で計算します。")
            }
            Section {
                Button("＋ 改定を追加") {
                    var r = rates[todayIndex]
                    r.id = UUID().uuidString
                    r.from = today
                    editing = RateEditTarget(rate: r, mode: .add(autofill: true))
                }
            } footer: {
                Text("昇給・最低賃金の改定・契約の更新など。過去の日付も、先の日付も入れられます。")
            }
            Section {
                Button("＋ これより前の時給を入れる") {
                    var r = rates[0]
                    r.id = UUID().uuidString
                    r.from = earliestEnd
                    editing = RateEditTarget(rate: r, mode: .earlier(maxEnd: earliestEnd))
                }
            } footer: {
                Text("いちばん古い設定より前の時給を、いつまでだったかと一緒に入れます。")
            }
        }
        .navigationTitle("給与の履歴")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { target in
            RateEditSheet(target: target, existing: rates) { saved in
                if case .earlier = target.mode {
                    rates = PayRate.insertEarlier(saved, endingOn: saved.from, into: rates)
                } else {
                    rates = PayRate.upsert(saved, into: rates)
                }
            }
        }
    }

    /// 「前の時給」の終わりの日として選べる最後の日。
    /// 次の改定の前日と、昨日のうち早いほう(いまの時給より前の時給を入れるため)
    private var earliestEnd: String {
        let yesterday = Rules.addDays(today, -1)
        guard rates.count > 1 else { return yesterday }
        return min(yesterday, Rules.addDays(rates[1].from, -1))
    }
}

struct RateEditTarget: Identifiable {
    enum Mode {
        /// 改定を追加。autofill なら、日付を変えたときに、その日の時点の設定を入れ直す
        case add(autofill: Bool)
        case edit
        /// いちばん古い設定より前の時給を入れる。rate.from には「いつまで」の日を入れる
        case earlier(maxEnd: String)
    }
    var rate: PayRate
    var mode: Mode
    var id: String { rate.id }

    var isNew: Bool {
        if case .edit = mode { return false }
        return true
    }
}

extension PayRate {
    /// r を入れる。同じ id、または同じ適用日のものは置き換える(日付の昇順、「最初」は先頭)
    static func upsert(_ r: PayRate, into a: [PayRate]) -> [PayRate] {
        var out = a.filter { $0.id != r.id && $0.from != r.from }
        out.append(r)
        out.sort { $0.from < $1.from }
        return out
    }

    /// いちばん古い設定より前に、end の日までの単価 r を入れる。
    /// これまでの「最初」の単価は end の翌日からの改定になり、r が新しい「最初」になる
    static func insertEarlier(_ r: PayRate, endingOn end: String, into a: [PayRate]) -> [PayRate] {
        guard let base = a.first, base.from.isEmpty else { return a }
        let start = Rules.addDays(end, 1)
        var newBase = r
        newBase.id = base.id
        newBase.from = ""
        var out = a
        out[0] = newBase
        // 次の改定がちょうど翌日から始まるなら、前の「最初」の単価はどこにも使われないので残さない
        if a.count < 2 || a[1].from > start {
            var moved = base
            moved.id = UUID().uuidString
            moved.from = start
            out = upsert(moved, into: out)
        }
        return out
    }
}

// MARK: - 改定を追加・編集

struct RateEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let target: RateEditTarget
    /// 同じ日付の改定があるか調べるための、いまの一覧
    let existing: [PayRate]
    let onSave: (PayRate) -> Void

    @State private var date: Date
    @State private var wage: String
    @State private var transport: String
    @State private var bonus: [String]
    @State private var holidayBonus: String
    @State private var confirmOverwrite = false
    /// 最後に自動で入れた単価(手で直していなければ、日付を変えたときに入れ直す)
    @State private var prefill: PayRate
    @FocusState private var focus: String?

    init(target: RateEditTarget, existing: [PayRate], onSave: @escaping (PayRate) -> Void) {
        self.target = target
        self.existing = existing
        self.onSave = onSave
        let r = target.rate
        _prefill = State(initialValue: r)
        _date = State(initialValue: Rules.parse(r.from) ?? Date())
        _wage = State(initialValue: Self.text(r.hourlyWage))
        _transport = State(initialValue: Self.text(r.transport))
        _bonus = State(initialValue: (0..<7).map { Self.text($0 < r.weekdayBonus.count ? r.weekdayBonus[$0] : 0) })
        _holidayBonus = State(initialValue: Self.text(r.holidayBonus))
    }

    private static func text(_ v: Int) -> String { v > 0 ? String(v) : "" }

    private var isBase: Bool { target.rate.from.isEmpty }
    private var fromText: String { isBase ? "" : Rules.format(date) }

    private var isEarlier: Bool {
        if case .earlier = target.mode { return true }
        return false
    }

    private var autofill: Bool {
        if case .add(let a) = target.mode { return a }
        return false
    }

    /// 「前の時給」で選べる、いちばん遅い日
    private var maxEndDate: Date {
        if case .earlier(let maxEnd) = target.mode, let d = Rules.parse(maxEnd) { return d }
        return Date()
    }

    /// 同じ日付の、別の改定(「前の時給」は日付の範囲を絞っているので、重ならない)
    private var clash: PayRate? {
        guard !isBase, !isEarlier else { return nil }
        return existing.first { $0.id != target.rate.id && $0.from == fromText }
    }

    private var title: String {
        switch target.mode {
        case .add: return "改定を追加"
        case .earlier: return "前の時給を入れる"
        case .edit: return isBase ? "最初の設定" : "改定を編集"
        }
    }

    /// 日付を変えたら、手で直していない限り、その日の時点の設定を入れ直す
    private func refill() {
        guard autofill, built.sameAmounts(prefill) else { return }
        let r = existing.last(where: { $0.from <= fromText }) ?? existing.first ?? prefill
        wage = Self.text(r.hourlyWage)
        transport = Self.text(r.transport)
        bonus = (0..<7).map { Self.text($0 < r.weekdayBonus.count ? r.weekdayBonus[$0] : 0) }
        holidayBonus = Self.text(r.holidayBonus)
        prefill = r
    }

    private var built: PayRate {
        PayRate(id: target.rate.id, from: fromText,
                hourlyWage: Int(wage) ?? 0, transport: Int(transport) ?? 0,
                weekdayBonus: bonus.map { Int($0) ?? 0 }, holidayBonus: Int(holidayBonus) ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isBase {
                        LabeledContent("適用する日", value: "最初から")
                    } else if isEarlier {
                        DatePicker("いつまで", selection: $date, in: ...maxEndDate, displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "ja_JP"))
                    } else {
                        DatePicker("適用する日", selection: $date, displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "ja_JP"))
                    }
                } footer: {
                    if isEarlier {
                        Text("この日までの予定を、ここに入れた時給で計算します")
                    } else if !isBase {
                        Text("この日より前の予定は、これまでの設定のまま計算します")
                    }
                }
                Section("給与") {
                    MoneyRow(label: "基本時給", text: $wage, focus: $focus, key: "wage")
                    MoneyRow(label: "交通費(片道)", text: $transport, focus: $focus, key: "transport")
                }
                Section {
                    BonusGrid(bonus: $bonus, focus: $focus)
                    MoneyRow(label: "祝日の加給", text: $holidayBonus, unit: "円/時", focus: $focus, key: "holiday")
                } header: {
                    Text("曜日・祝日加給(円/時)")
                } footer: {
                    if isEarlier {
                        Text("いちばん古い設定を入れてあります。前の時給に直してください。")
                    } else if autofill {
                        Text("選んだ日の時点の設定を入れてあります。変わるところだけ直してください。")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: date) { refill() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(target.isNew ? "追加" : "保存") {
                        focus = nil
                        if clash != nil { confirmOverwrite = true } else { finish() }
                    }
                    .disabled(focus != nil)
                }
            }
            .keyboardDismissBar { focus = nil }
            .alert("\(WorkplaceSummary.date(fromText))の改定は、すでにあります。上書きしますか?",
                   isPresented: $confirmOverwrite) {
                Button("上書きする", role: .destructive) { finish() }
                Button("キャンセル", role: .cancel) {}
            }
        }
        .presentationDetents([.large])
    }

    private func finish() {
        onSave(built)
        dismiss()
    }
}

// MARK: - 休憩ルールの 1 行

struct BreakRuleRow: View {
    @Binding var rule: BreakRuleDraft
    var focus: FocusState<String?>.Binding
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            TextField("0", text: Binding(
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
                .frame(width: 40)
                .focused(focus, equals: "rule-h-" + rule.id)
            Text("時間").lineLimit(1).fixedSize()
            Picker("条件", selection: $rule.comparison) {
                Text("以上").tag(BreakComparison.atLeast)
                Text("を超える").tag(BreakComparison.over)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            Spacer(minLength: 0)
            TextField("0", text: Binding(
                get: { rule.minutes },
                set: { input in
                    rule.minutes = String(input.filter { $0.isASCII && $0.isNumber }.prefix(3))
                }))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 34)
                .focused(focus, equals: "rule-m-" + rule.id)
            Text("分").lineLimit(1).fixedSize()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("削除")
        }
    }
}
