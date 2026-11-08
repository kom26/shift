import UIKit

/// 24時をこえる時間の種類
enum OvernightKind: String, Equatable {
    /// 開始は24時前で、終了が24時をこえる(22:00〜30:00 など)
    case lateEnd
    /// 開始が24時以降(24:00〜30:00 など)
    case afterMidnight
}

/// 終了が24時をこえる予定の取り込み方
enum LateEndChoice: String, CaseIterable, Equatable {
    /// 22:00〜30:00 のまま、その日に収める
    case fit
    /// 22:00〜翌日6:00 の日またぎにする
    case cross
}

/// 開始が24時以降の予定の取り込み方
enum AfterMidnightChoice: String, CaseIterable, Equatable {
    /// 24:00〜30:00 のまま
    case keep
    /// 24:00〜翌日6:00 の日またぎにする
    case cross
    /// 翌日の 0:00〜6:00 として、翌日に置く
    case next
}

struct OvernightChoices: Equatable {
    var lateEnd = LateEndChoice.fit
    var afterMidnight = AfterMidnightChoice.keep
}

/// 同じ時間の組み合わせ(例: 22:00〜30:00)とその日付
struct OvernightPattern: Identifiable, Equatable {
    let start: String
    let end: String
    var dates: [String]
    var id: String { start + "-" + end }
}

struct OvernightGroup: Identifiable, Equatable {
    let kind: OvernightKind
    var patterns: [OvernightPattern]
    var id: String { kind.rawValue }
    var dayCount: Int { patterns.reduce(0) { $0 + $1.dates.count } }
    /// いちばん日数の多い組み合わせ(説明の例に使う)
    var representative: OvernightPattern? { patterns.max { $0.dates.count < $1.dates.count } }
}

extension ShiftLine {
    /// 24時をこえる時間か(休みと、時間のない行は nil)。24:00 ちょうどまでの終了は、こえるに入れない
    var overnightKind: OvernightKind? {
        guard !off, let s = Rules.minutes(start), let e = Rules.minutes(end) else { return nil }
        if s >= 1440 { return .afterMidnight }
        return e > 1440 ? .lateEnd : nil
    }
}

/// 読み取った 1 日分(ShiftLine)から、予定を作る
enum ShiftLineImport {
    /// 分から "HH:mm"
    static func timeText(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    /// 24時をこえる時間を、種類ごと・時間の組み合わせごとにまとめる(日付順)
    static func overnightGroups(of lines: [ShiftLine]) -> [OvernightGroup] {
        var out: [OvernightGroup] = []
        for kind in [OvernightKind.lateEnd, .afterMidnight] {
            var patterns: [OvernightPattern] = []
            for line in lines where line.overnightKind == kind {
                guard let s = line.start, let e = line.end else { continue }
                if let i = patterns.firstIndex(where: { $0.start == s && $0.end == e }) {
                    patterns[i].dates.append(line.date)
                } else {
                    patterns.append(OvernightPattern(start: s, end: e, dates: [line.date]))
                }
            }
            if !patterns.isEmpty { out.append(OvernightGroup(kind: kind, patterns: patterns)) }
        }
        return out
    }

    /// 年月の表記がない写真のために、読み取った日付の年月を、選んだ年月に合わせる。
    /// 月をまたぐ表は、いちばん早い日からの月の差を保つ(選んだ月から数える)。その月に無い日(2/30 など)は捨てる
    static func alignYearMonth(_ lines: [ShiftLine], year: Int, month: Int) -> [ShiftLine] {
        guard let first = lines.min(by: { $0.date < $1.date }) else { return lines }
        let f = Rules.ymd(first.date)
        let base = f.year * 12 + (f.month - 1)
        let target = year * 12 + (month - 1)
        return lines.compactMap { line in
            let p = Rules.ymd(line.date)
            let index = p.year * 12 + (p.month - 1) - base + target
            // その月に無い日(2/30 など)は捨てる
            guard DateComponents(calendar: Calendar(identifier: .gregorian), year: index / 12, month: index % 12 + 1, day: p.day).isValidDate else { return nil }
            let date = String(format: "%04d-%02d-%02d", index / 12, index % 12 + 1, p.day)
            var out = line
            out.date = date
            return out
        }
    }

    /// 選んだ取り込み方を当てはめた行。24時をこえない行は、そのまま
    static func resolved(_ line: ShiftLine, _ choices: OvernightChoices) -> ShiftLine {
        guard let kind = line.overnightKind, let s = Rules.minutes(line.start), let e = Rules.minutes(line.end) else { return line }
        var out = line
        switch kind {
        case .lateEnd:
            // 日またぎ: 終了を、翌日の時刻に書き直す(終了日は、取り込みのときに翌日になる)
            if choices.lateEnd == .cross { out.end = timeText(e - 1440) }
        case .afterMidnight:
            switch choices.afterMidnight {
            case .keep: break
            case .cross:
                if e >= 1440 { out.end = timeText(e - 1440) }
            case .next:
                out.date = Rules.addDays(line.date, 1)
                out.start = timeText(s - 1440)
                if e >= 1440 { out.end = timeText(e - 1440) }
            }
        }
        return out
    }

    /// 読み取り結果から、追加する予定を作る。休みの日は作らない。
    /// 職場を選んでいれば勤務予定(休憩は職場の標準で、労働時間も入れる)、そうでなければラベルの通常予定
    static func events(from lines: [ShiftLine], title: String, workplace: Workplace?, label: EventLabel?,
                       store: Store) -> [ShiftEvent] {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let color = store.groupColor(workplaceId: workplace?.id, labelId: workplace == nil ? label?.id : nil)
        return lines.filter { !$0.off }.map { line in
            let allDay = line.start == nil || line.end == nil
            let st = allDay ? nil : line.start
            let et = allDay ? nil : line.end
            let endDate = allDay
                ? line.date
                : (Rules.resolveEndDate(start: line.date, end: line.date, allDay: false, startTime: st, endTime: et) ?? line.date)
            var hours: Double?
            if !allDay {
                let span = Rules.spanMinutes(startDate: line.date, startTime: st, endDate: endDate, endTime: et)
                let rest = span.map { BreakRules.minutes(span: $0, rules: workplace?.breakRules ?? []) } ?? 0
                hours = Rules.workHours(startDate: line.date, startTime: st, endDate: endDate, endTime: et,
                                        allDay: false, breakMinutes: rest)
            }
            var e = ShiftEvent.new(on: line.date)
            e.title = name
            e.color = color
            e.endDate = endDate
            e.allDay = allDay
            e.startTime = st
            e.endTime = et
            e.workHours = hours
            e.workplaceId = workplace?.id
            e.labelId = workplace == nil ? label?.id : nil
            // バーの表記は、編集画面の初期と同じ(勤務予定は時間、通常予定は予定名)
            e.barShowsTitle = workplace == nil ? true : nil
            e.source = ShiftEvent.screenshotSource
            return e
        }
    }
}

/// 読み取りに送る前に、画像を小さくする(通信と、読み取りの費用を抑える。長辺 1568px は、API が自分で縮める大きさ)
enum ImageShrinker {
    static func jpeg(from image: UIImage, maxSide: CGFloat = 1568, quality: CGFloat = 0.8) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxSide / longest)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
