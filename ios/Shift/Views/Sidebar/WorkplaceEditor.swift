import SwiftUI

struct WorkplaceEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// nil なら新規
    let workplace: Workplace?

    @State private var name: String
    @State private var color: String
    /// 給与の単価。先頭が「最初」、そのあとに改定が日付の昇順
    @State private var rates: [PayRate]
    /// 下の 4 つは「今日の時点」の単価の入力欄
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
    @State private var isDaily: Bool
    @State private var dailyMonthly: Bool
    @State private var confirmApply = false
    /// 単価を変えて保存したときの「いつからの設定ですか?」
    @State private var askRateDate = false
    /// 「これまでの予定」のうち、入力ミスを直すと給与が変わる数
    @State private var pastCount = 0
    /// 「日付を選ぶ」で開く改定の画面
    @State private var pickingRate: RateEditTarget?
    /// 改定の画面で追加したら、閉じたあとに保存を続ける
    @State private var continueSave = false
    @FocusState private var focus: String?

    private let today = Rules.today()

    init(workplace: Workplace?) {
        self.workplace = workplace
        _name = State(initialValue: workplace?.name ?? "")
        _color = State(initialValue: workplace?.color ?? Store.defaultColors[1])
        let rates = workplace?.payRates
            ?? [PayRate(id: "base", from: "", hourlyWage: 0, transport: 0, weekdayBonus: [], holidayBonus: 0)]
        _rates = State(initialValue: rates)
        let r = rates.last(where: { $0.from <= Rules.today() }) ?? rates[0]
        _wage = State(initialValue: Self.text(r.hourlyWage))
        _transport = State(initialValue: Self.text(r.transport))
        _bonus = State(initialValue: (0..<7).map { Self.text($0 < r.weekdayBonus.count ? r.weekdayBonus[$0] : 0) })
        _holidayBonus = State(initialValue: Self.text(r.holidayBonus))
        _rules = State(initialValue: (workplace?.breakRules ?? []).map { BreakRuleDraft(rule: $0) })
        _breakFromNight = State(initialValue: workplace?.breakFromNight ?? true)
        _closingDay = State(initialValue: workplace?.closingDay ?? 0)
        _paydayOn = State(initialValue: workplace?.paydayDay != nil)
        _paydayDay = State(initialValue: workplace?.paydayDay ?? 25)
        _paydayOffset = State(initialValue: workplace?.paydayMonthOffset ?? 1)
        _isDaily = State(initialValue: workplace?.isDaily ?? false)
        _dailyMonthly = State(initialValue: workplace?.dailyPaidMonthly ?? false)
    }

    private static func text(_ v: Int?) -> String {
        guard let v, v > 0 else { return "" }
        return String(v)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var affectedCount: Int {
        guard let workplace else { return 0 }
        return store.eventCount(forWorkplace: workplace.id)
    }
    private var changed: Bool {
        guard let workplace else { return false }
        return trimmed != workplace.name || color != workplace.color
    }

    // MARK: 単価

    /// 今日の時点で使っている単価の位置
    private var todayIndex: Int { rates.lastIndex(where: { $0.from <= today }) ?? 0 }
    private var currentRate: PayRate { rates[todayIndex] }

    /// 入力欄の単価(id・日付は今日の時点のもの)
    private var draftRate: PayRate {
        var r = currentRate
        r.hourlyWage = Int(wage) ?? 0
        r.transport = Int(transport) ?? 0
        r.weekdayBonus = Workplace.normalizedBonus(bonus.map { Int($0) ?? 0 })
        r.holidayBonus = Int(holidayBonus) ?? 0
        return r
    }

    private var rateEdited: Bool { !draftRate.sameAmounts(currentRate) }

    /// 入力欄を、今日の時点の単価にそろえる(履歴の画面で直したあと)
    private func syncFieldsFromRates() {
        let r = currentRate
        wage = Self.text(r.hourlyWage)
        transport = Self.text(r.transport)
        bonus = (0..<7).map { Self.text($0 < r.weekdayBonus.count ? r.weekdayBonus[$0] : 0) }
        holidayBonus = Self.text(r.holidayBonus)
    }

    /// 今日の時点の区切りの、始まりの文言(「最初から」または「2026年10月1日から」)
    private var currentFromLabel: String {
        currentRate.from.isEmpty ? "最初から" : WorkplaceSummary.date(currentRate.from) + "から"
    }

    /// 確認に出す、何を変えたかの文
    private var rateChangeMessage: String {
        let a = currentRate, b = draftRate
        var head: String
        if a.hourlyWage != b.hourlyWage {
            head = "基本時給を \(WorkplaceSummary.yen(a.hourlyWage)) から \(WorkplaceSummary.yen(b.hourlyWage)) に変えました。"
        } else {
            var items: [String] = []
            if a.transport != b.transport { items.append("交通費") }
            if a.weekdayBonus != b.weekdayBonus || a.holidayBonus != b.holidayBonus { items.append("曜日・祝日加給") }
            head = items.joined(separator: "・") + "を変えました。"
        }
        head += "入力ミスを直すときは、これまでの予定 \(pastCount)件の給与も変わります"
        return head
    }

    /// 先の日付の改定(いちばん近いもの)の文言
    private var upcomingText: String? {
        guard let next = rates.first(where: { $0.from > today }) else { return nil }
        let prev = rates.last(where: { $0.from < next.from }) ?? rates[0]
        if next.hourlyWage != prev.hourlyWage {
            return "\(WorkplaceSummary.date(next.from))から \(WorkplaceSummary.yen(next.hourlyWage))に変わります"
        }
        return "\(WorkplaceSummary.date(next.from))から 設定が変わります"
    }

    // MARK: 画面

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("職場の名前", text: $name)
                        .focused($focus, equals: "name")
                }
                Section("色") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Store.defaultColors, id: \.self) { c in
                                ColorDot(hex: c, size: 24)
                                    .overlay(Circle().stroke(Color.primary, lineWidth: color == c ? 2 : 0).padding(-3))
                                    .onTapGesture { color = c }
                            }
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 5)
                    }
                    CustomColorButton(color: $color)
                }
                Section {
                    TwoWayPicker("給与の形態", selection: $isDaily, first: ("時給", false), second: ("日給", true))
                    if isDaily {
                        Text("日給は予定ごとに入力します")
                            .font(.app(12))
                            .foregroundStyle(.secondary)
                    } else {
                        MoneyRow(label: "基本時給", text: $wage, focus: $focus, key: "wage")
                        MoneyRow(label: "交通費(片道)", text: $transport, focus: $focus, key: "transport")
                        NavigationLink {
                            BonusPage(bonus: $bonus, holidayBonus: $holidayBonus)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("曜日・祝日加給")
                                Text(WorkplaceSummary.bonus(weekday: bonus.map { Int($0) ?? 0 },
                                                            holiday: Int(holidayBonus) ?? 0))
                                    .font(.app(13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        NavigationLink {
                            WageHistoryPage(rates: $rates, today: today)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("給与の履歴")
                                    if let upcomingText {
                                        Text(upcomingText)
                                            .font(.app(13))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text("\(rates.count)件")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("給与")
                } footer: {
                    if !isDaily {
                        Text("交通費は1予定ごとに往復(×2)で計算します")
                    }
                }
                Section("勤務と支払い") {
                    if !isDaily {
                        NavigationLink {
                            BreakPage(rules: $rules, breakFromNight: $breakFromNight)
                        } label: {
                            LabeledContent("休憩", value: WorkplaceSummary.breaks(BreakRuleDraft.clean(rules)))
                        }
                    }
                    NavigationLink {
                        PaydayPage(isDaily: isDaily, dailyMonthly: $dailyMonthly, closingDay: $closingDay,
                                   paydayOn: $paydayOn, paydayDay: $paydayDay, paydayOffset: $paydayOffset)
                    } label: {
                        LabeledContent("給料日", value: WorkplaceSummary.payday(
                            isDaily: isDaily, dailyMonthly: dailyMonthly, closingDay: closingDay,
                            paydayDay: paydayOn ? paydayDay : nil, offset: paydayOffset))
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(workplace == nil ? "職場を追加" : "職場を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(trimmed.isEmpty || focus != nil)
                }
            }
            .keyboardDismissBar { focus = nil }
            .onChange(of: rates) { syncFieldsFromRates() }
            .confirmationDialog("いつからの設定ですか?", isPresented: $askRateDate, titleVisibility: .visible) {
                Button("今日(\(WorkplaceSummary.monthDay(today)))から") {
                    var r = draftRate
                    r.id = UUID().uuidString
                    r.from = today
                    rates = PayRate.upsert(r, into: rates)
                    finishSaveAfterDialog()
                }
                Button("日付を選ぶ") {
                    var r = draftRate
                    r.id = UUID().uuidString
                    r.from = today
                    pickingRate = RateEditTarget(rate: r, mode: .add(autofill: false))
                }
                Button("\(currentFromLabel)(入力ミスを直す)") {
                    overwriteCurrentRate()
                    finishSaveAfterDialog()
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text(rateChangeMessage)
            }
            .sheet(item: $pickingRate, onDismiss: {
                if continueSave {
                    continueSave = false
                    finishSave()
                }
            }) { target in
                RateEditSheet(target: target, existing: rates) { saved in
                    rates = PayRate.upsert(saved, into: rates)
                    continueSave = true
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

    // MARK: 保存

    private func save() {
        focus = nil
        if let workplace, !isDaily, rateEdited {
            // 今日の時点の区切りに入る、今日より前の予定があれば、いつからの設定か聞く
            let from = currentRate.from.isEmpty ? nil : currentRate.from
            pastCount = store.eventCount(forWorkplace: workplace.id, from: from, through: Rules.addDays(today, -1))
            if pastCount > 0 {
                askRateDate = true
                return
            }
        }
        overwriteCurrentRate()
        finishSave()
    }

    /// 入力欄の単価で、今日の時点の区切りを書き換える
    private func overwriteCurrentRate() {
        guard rateEdited else { return }
        rates[todayIndex] = draftRate
    }

    private func finishSave() {
        if workplace != nil, changed, affectedCount >= 1 {
            confirmApply = true
        } else {
            commit(applyToEvents: false)
        }
    }

    /// 確認が閉じきる前に次の確認を出すと出ないことがあるので、少し待ってから続ける
    private func finishSaveAfterDialog() {
        if workplace != nil, changed, affectedCount >= 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { confirmApply = true }
        } else {
            commit(applyToEvents: false)
        }
    }

    private func built(id: String) -> Workplace {
        var w = Workplace(id: id, name: trimmed, color: color,
                          breakRules: BreakRuleDraft.clean(rules),
                          breakFromNight: breakFromNight,
                          closingDay: closingDay,
                          paydayDay: (paydayOn && (!isDaily || dailyMonthly)) ? paydayDay : nil,
                          paydayMonthOffset: paydayOffset,
                          payType: isDaily ? .daily : .hourly,
                          dailyPaidMonthly: isDaily && dailyMonthly)
        w.payRates = rates
        return w
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
