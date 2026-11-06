import UIKit

/// 読み取った 1 日分(ShiftLine)から、予定を作る
enum ShiftLineImport {
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
