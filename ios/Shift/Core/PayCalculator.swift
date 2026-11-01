import Foundation

struct PayBreakdown: Equatable {
    var base: Double
    var night: Double
    var overtime: Double
    var bonus: Double
    var transport: Double
    var total: Double
    var netMinutes: Int
    var nightMinutes: Int
    var overtimeMinutes: Int
    /// 一律加給・調整給(手入力。total に含む)
    var adjustment: Double = 0
    /// 曜日・祝日加給の対象になった分数(加給がない日は 0)
    var bonusMinutes: Int = 0

    static let zero = PayBreakdown(base: 0, night: 0, overtime: 0, bonus: 0, transport: 0, total: 0,
                                   netMinutes: 0, nightMinutes: 0, overtimeMinutes: 0)

    static func + (a: PayBreakdown, b: PayBreakdown) -> PayBreakdown {
        PayBreakdown(base: a.base + b.base, night: a.night + b.night, overtime: a.overtime + b.overtime,
                     bonus: a.bonus + b.bonus, transport: a.transport + b.transport, total: a.total + b.total,
                     netMinutes: a.netMinutes + b.netMinutes, nightMinutes: a.nightMinutes + b.nightMinutes,
                     overtimeMinutes: a.overtimeMinutes + b.overtimeMinutes,
                     adjustment: a.adjustment + b.adjustment, bonusMinutes: a.bonusMinutes + b.bonusMinutes)
    }
}

enum PayCalculator {
    /// 深夜帯(開始日0:00からの分): [0,300) と、各日k>=0の [1440k+1320, 1440k+1740)(22:00-翌5:00)。
    /// 二重計上しないよう、翌朝の窓は別に足さない
    private static func nightOverlap(start s: Int, span: Int) -> Int {
        let end = s + span
        var n = max(0, min(end, 300) - max(s, 0))
        var k = 0
        while 1440 * k + 1320 < end {
            let a = 1440 * k + 1320, b = 1440 * k + 1740
            n += max(0, min(end, b) - max(s, a))
            k += 1
        }
        return n
    }

    /// 日付を含む拘束時間のうち、深夜帯と重なる分数
    static func nightMinutes(startDate: String?, startTime: String?, endDate: String?, endTime: String?) -> Int {
        guard let s = Rules.minutes(startTime),
              let span = Rules.spanMinutes(startDate: startDate, startTime: startTime,
                                           endDate: endDate, endTime: endTime) else { return 0 }
        return nightOverlap(start: s, span: span)
    }

    /// 開始・終了時刻(HH:mm)の拘束時間のうち、深夜帯(22:00-翌5:00)と重なる分数
    static func nightMinutes(startTime: String?, endTime: String?) -> Int {
        guard let s = Rules.minutes(startTime),
              let span = Rules.totalMinutes(start: startTime, end: endTime) else { return 0 }
        return nightOverlap(start: s, span: span)
    }

    static func pay(event: ShiftEvent, workplace: Workplace, isHoliday: Bool) -> PayBreakdown? {
        guard !event.allDay,
              let s = Rules.minutes(event.startTime),
              let span = Rules.spanMinutes(startDate: event.startDate, startTime: event.startTime,
                                           endDate: event.endDate, endTime: event.endTime) else { return nil }

        let brk: Int
        if let wh = event.workHours {
            brk = max(0, Int((Double(span) - wh * 60).rounded()))
        } else {
            brk = BreakRules.minutes(span: span, rules: workplace.breakRules)
        }
        let net = span - brk
        guard net > 0 else { return nil }

        let n = nightOverlap(start: s, span: span)
        let d = span - n

        let fromNight = event.breakInNight ?? workplace.breakFromNight
        let nn: Int
        if fromNight {
            let takeN = min(brk, n)
            nn = n - takeN
        } else {
            let takeD = min(brk, d)
            nn = n - (brk - takeD)
        }

        let overtime = max(0, net - 480)
        let wage = Double(workplace.hourlyWage)
        let bonusRate: Int
        if isHoliday {
            bonusRate = workplace.holidayBonus
        } else if let sd = event.startDate, workplace.weekdayBonus.count == 7 {
            bonusRate = workplace.weekdayBonus[Rules.weekday(sd)]
        } else {
            bonusRate = 0
        }

        let base = Double(net) / 60 * wage
        let night = Double(nn) / 60 * wage * 0.25
        let ot = Double(overtime) / 60 * wage * 0.25
        let bonus = Double(net) / 60 * Double(bonusRate)
        let transport = Double(workplace.transport) * 2  // 片道 × 2(往復)
        let adjustment = Double(event.adjustment ?? 0)
        return PayBreakdown(base: base, night: night, overtime: ot, bonus: bonus, transport: transport,
                            total: base + night + ot + bonus + transport + adjustment,
                            netMinutes: net, nightMinutes: nn, overtimeMinutes: overtime,
                            adjustment: adjustment, bonusMinutes: bonusRate > 0 ? net : 0)
    }
}
