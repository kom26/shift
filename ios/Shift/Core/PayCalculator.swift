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
        return PayBreakdown(base: base, night: night, overtime: ot, bonus: bonus, transport: transport,
                            total: base + night + ot + bonus + transport,
                            netMinutes: net, nightMinutes: nn, overtimeMinutes: overtime)
    }
}
