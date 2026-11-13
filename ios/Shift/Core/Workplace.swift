import Foundation

enum BreakComparison: String, Codable {
    case atLeast  // 以上
    case over     // を超える
}

struct BreakRule: Codable, Equatable, Identifiable {
    var id: String
    var hours: Double
    var comparison: BreakComparison
    var minutes: Int
}

/// タイトルと色のプリセット + 給与設定。予定とは workplaceId(またはタイトル一致)で結びつく
struct Workplace: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var color: String
    var hourlyWage: Int
    var transport: Int
    var weekdayBonus: [Int]
    var holidayBonus: Int
    var breakRules: [BreakRule]
    var breakFromNight: Bool
    /// 締め日。0 = 末日、1...31(月の日数で丸める)
    var closingDay: Int
    /// 給料日。nil = 未設定、0 = 末日、1...31(月の日数で丸める)
    var paydayDay: Int?
    /// 締め月から何か月後が給料日か。0 = 当月、1 = 翌月、2 = 翌々月
    var paydayMonthOffset: Int
    /// 給与の形態。日給の職場は、予定ごとに日給を手入力する(時給・交通費・加給・休憩は使わない)
    var payType: PayType
    /// 日給のとき、月払い(締め日・給料日あり)か。false は日払い
    var dailyPaidMonthly: Bool
    /// 給与の改定(昇給・最低賃金・契約更新など)。from の昇順。
    /// 上の hourlyWage・transport・weekdayBonus・holidayBonus は「最初」の設定で、
    /// 予定の給与は開始日の時点の設定で計算する(resolved(on:))
    var rateChanges: [PayRate]

    enum PayType: String, Codable { case hourly, daily }

    var isDaily: Bool { payType == .daily }

    init(id: String, name: String, color: String,
         hourlyWage: Int = 0, transport: Int = 0,
         weekdayBonus: [Int] = [0, 0, 0, 0, 0, 0, 0],
         holidayBonus: Int = 0, breakRules: [BreakRule] = [],
         breakFromNight: Bool = true,
         closingDay: Int = 0, paydayDay: Int? = nil, paydayMonthOffset: Int = 1,
         payType: PayType = .hourly, dailyPaidMonthly: Bool = false,
         rateChanges: [PayRate] = []) {
        self.payType = payType
        self.dailyPaidMonthly = dailyPaidMonthly
        self.id = id
        self.name = name
        self.color = color
        self.hourlyWage = hourlyWage
        self.transport = transport
        self.weekdayBonus = Workplace.normalizedBonus(weekdayBonus)
        self.holidayBonus = holidayBonus
        self.breakRules = breakRules
        self.breakFromNight = breakFromNight
        self.closingDay = closingDay
        self.paydayDay = paydayDay
        self.paydayMonthOffset = min(max(paydayMonthOffset, 0), 2)
        self.rateChanges = PayRate.sorted(rateChanges)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, color, hourlyWage, transport, weekdayBonus, holidayBonus, breakRules, breakFromNight
        case closingDay, paydayDay, paydayMonthOffset, payType, dailyPaidMonthly, rateChanges
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        color = try c.decode(String.self, forKey: .color)
        hourlyWage = try c.decodeIfPresent(Int.self, forKey: .hourlyWage) ?? 0
        transport = try c.decodeIfPresent(Int.self, forKey: .transport) ?? 0
        weekdayBonus = Workplace.normalizedBonus(try c.decodeIfPresent([Int].self, forKey: .weekdayBonus) ?? [])
        holidayBonus = try c.decodeIfPresent(Int.self, forKey: .holidayBonus) ?? 0
        breakRules = try c.decodeIfPresent([BreakRule].self, forKey: .breakRules) ?? []
        breakFromNight = try c.decodeIfPresent(Bool.self, forKey: .breakFromNight) ?? true
        closingDay = try c.decodeIfPresent(Int.self, forKey: .closingDay) ?? 0
        paydayDay = try c.decodeIfPresent(Int.self, forKey: .paydayDay)
        paydayMonthOffset = min(max(try c.decodeIfPresent(Int.self, forKey: .paydayMonthOffset) ?? 1, 0), 2)
        payType = try c.decodeIfPresent(PayType.self, forKey: .payType) ?? .hourly
        dailyPaidMonthly = try c.decodeIfPresent(Bool.self, forKey: .dailyPaidMonthly) ?? false
        rateChanges = PayRate.sorted(try c.decodeIfPresent([PayRate].self, forKey: .rateChanges) ?? [])
    }

    /// 7要素(0=日曜)に揃える
    static func normalizedBonus(_ a: [Int]) -> [Int] {
        if a.count == 7 { return a }
        return Array((a + Array(repeating: 0, count: 7)).prefix(7))
    }
}

/// 給与の単価(時給・交通費・曜日の加給・祝日の加給)と、その適用を始める日
struct PayRate: Codable, Equatable, Identifiable {
    var id: String
    /// 適用を始める日(yyyy-MM-dd)。"" は「最初から」
    var from: String
    var hourlyWage: Int
    var transport: Int
    var weekdayBonus: [Int]
    var holidayBonus: Int

    init(id: String = UUID().uuidString, from: String, hourlyWage: Int, transport: Int,
         weekdayBonus: [Int], holidayBonus: Int) {
        self.id = id
        self.from = from
        self.hourlyWage = hourlyWage
        self.transport = transport
        self.weekdayBonus = Workplace.normalizedBonus(weekdayBonus)
        self.holidayBonus = holidayBonus
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        from = try c.decodeIfPresent(String.self, forKey: .from) ?? ""
        hourlyWage = try c.decodeIfPresent(Int.self, forKey: .hourlyWage) ?? 0
        transport = try c.decodeIfPresent(Int.self, forKey: .transport) ?? 0
        weekdayBonus = Workplace.normalizedBonus(try c.decodeIfPresent([Int].self, forKey: .weekdayBonus) ?? [])
        holidayBonus = try c.decodeIfPresent(Int.self, forKey: .holidayBonus) ?? 0
    }

    /// 単価だけを比べる(id・日付は見ない)
    func sameAmounts(_ o: PayRate) -> Bool {
        hourlyWage == o.hourlyWage && transport == o.transport
            && weekdayBonus == o.weekdayBonus && holidayBonus == o.holidayBonus
    }

    /// 日付の昇順。同じ日付が重なったら、あとのものを残す
    static func sorted(_ a: [PayRate]) -> [PayRate] {
        var byDate: [String: PayRate] = [:]
        for r in a where !r.from.isEmpty { byDate[r.from] = r }
        return byDate.values.sorted { $0.from < $1.from }
    }
}

extension Workplace {
    /// 「最初」の設定を先頭に、改定を日付の昇順に並べたもの
    var payRates: [PayRate] {
        get {
            [PayRate(id: "base", from: "", hourlyWage: hourlyWage, transport: transport,
                     weekdayBonus: weekdayBonus, holidayBonus: holidayBonus)] + rateChanges
        }
        set {
            if let base = newValue.first(where: { $0.from.isEmpty }) {
                hourlyWage = base.hourlyWage
                transport = base.transport
                weekdayBonus = Workplace.normalizedBonus(base.weekdayBonus)
                holidayBonus = base.holidayBonus
            }
            rateChanges = PayRate.sorted(newValue)
        }
    }

    /// date(yyyy-MM-dd)の時点で使う単価
    func rate(on date: String) -> PayRate {
        payRates.last(where: { $0.from <= date }) ?? payRates[0]
    }

    /// date の時点の単価を、上の4項目に入れた職場(PayCalculator にそのまま渡せる)
    func resolved(on date: String?) -> Workplace {
        guard !rateChanges.isEmpty else { return self }
        let r = rate(on: date ?? Rules.today())
        var w = self
        w.hourlyWage = r.hourlyWage
        w.transport = r.transport
        w.weekdayBonus = r.weekdayBonus
        w.holidayBonus = r.holidayBonus
        return w
    }
}

/// 職場の設定画面に出す要約の文言
enum WorkplaceSummary {
    private static let dayLabels = ["日", "月", "火", "水", "木", "金", "土"]

    static func yen(_ v: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return (f.string(from: NSNumber(value: v)) ?? String(v)) + "円"
    }

    /// 2027-04-01 → 2027年4月1日
    static func date(_ s: String) -> String {
        let p = Rules.ymd(s)
        return "\(p.year)年\(p.month)月\(p.day)日"
    }

    /// 2026-11-14 → 11月14日
    static func monthDay(_ s: String) -> String {
        let p = Rules.ymd(s)
        return "\(p.month)月\(p.day)日"
    }

    /// 例: 「土日 +100円/時 ・ 祝日 +150円/時」。加給がなければ「なし」
    static func bonus(weekday: [Int], holiday: Int) -> String {
        var parts: [String] = []
        // 月曜はじまりで、同じ額の曜日をまとめる
        let order = [1, 2, 3, 4, 5, 6, 0]
        var seen: [Int] = []
        for d in order where d < weekday.count && weekday[d] > 0 && !seen.contains(weekday[d]) {
            seen.append(weekday[d])
        }
        for amount in seen {
            let days = order.filter { $0 < weekday.count && weekday[$0] == amount }
            let label: String
            if Set(days) == [0, 6] { label = "土日" }
            else if Set(days) == [1, 2, 3, 4, 5] { label = "平日" }
            else if days.count == 7 { label = "毎日" }
            else { label = days.map { dayLabels[$0] }.joined() }
            parts.append("\(label) +\(yen(amount))/時")
        }
        if holiday > 0 { parts.append("祝日 +\(yen(holiday))/時") }
        return parts.isEmpty ? "なし" : parts.joined(separator: " ・ ")
    }

    static func breaks(_ rules: [BreakRule]) -> String {
        rules.isEmpty ? "法定どおり" : "独自 \(rules.count)件"
    }

    static func payday(isDaily: Bool, dailyMonthly: Bool, closingDay: Int, paydayDay: Int?, offset: Int) -> String {
        if isDaily && !dailyMonthly { return "日払い" }
        let closing = closingDay == 0 ? "末日締め" : "\(closingDay)日締め"
        guard let paydayDay else { return closing }
        let month = ["当月", "翌月", "翌々月"][min(max(offset, 0), 2)]
        let day = paydayDay == 0 ? "末日" : "\(paydayDay)日"
        return "\(closing)・\(month)\(day)払い"
    }
}
