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
    /// 深夜帯(分): 0:00-5:00、22:00-29:00、46:00-53:00
    private static let nightIntervals: [(Int, Int)] = [(0, 300), (1320, 1740), (2760, 3180)]

    static func pay(event: ShiftEvent, workplace: Workplace, isHoliday: Bool) -> PayBreakdown? {
        guard !event.allDay,
              let s = Rules.minutes(event.startTime),
              let span = Rules.totalMinutes(start: event.startTime, end: event.endTime) else { return nil }

        let brk: Int
        if let wh = event.workHours {
            brk = max(0, Int((Double(span) - wh * 60).rounded()))
        } else {
            brk = BreakRules.minutes(span: span, rules: workplace.breakRules)
        }
        let net = span - brk
        guard net > 0 else { return nil }

        var n = 0
        for (a, b) in nightIntervals {
            n += max(0, min(s + span, b) - max(s, a))
        }
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
        let transport = Double(workplace.transport)
        return PayBreakdown(base: base, night: night, overtime: ot, bonus: bonus, transport: transport,
                            total: base + night + ot + bonus + transport,
                            netMinutes: net, nightMinutes: nn, overtimeMinutes: overtime)
    }
}
