import Foundation

/// 写真の一覧の 1 枚(予定か開始・締切に付けた画像)
struct AlbumPhoto: Identifiable, Equatable {
    enum Source: Equatable {
        case event
        case task
    }

    /// 一覧の中で一意の名前("e:" 予定 / "t:" 開始・締切 / "s:" 共有カレンダーの予定 + その ID)
    let id: String
    let imageId: String
    /// その予定の日付(複数日の予定は、始まりの日)。nil は日付未定
    let date: String?
    let title: String
    let source: Source
    /// 勤務予定の職場
    var workplaceId: String? = nil
    /// 通常予定のラベル(指定なしは Store.noLabelKey)。勤務予定・開始締切・共有の予定は nil
    var labelKey: String? = nil
}

/// 写真の一覧の絞り込み(自分のカレンダーだけ)
enum AlbumFilter: Hashable {
    case all
    case workplace(String)
    case label(String)
    case tasks
}

/// 写真の一覧の、月ごとのまとまり
struct AlbumSection: Identifiable, Equatable {
    /// "2026-11" / 日付未定は ""
    let id: String
    let title: String
    let photos: [AlbumPhoto]
}

enum PhotoAlbum {
    /// 自分のカレンダーの写真。予定と、開始・締切に付けた画像。重ねている共有カレンダーの予定は含めない
    static func own(store: Store) -> [AlbumPhoto] {
        var out: [AlbumPhoto] = []
        for e in store.events {
            guard let image = e.imageId else { continue }
            let workplace = store.workplace(for: e)?.id
            out.append(AlbumPhoto(id: "e:" + e.id, imageId: image, date: e.placed ? e.startDate : nil,
                                  title: e.title, source: .event, workplaceId: workplace,
                                  labelKey: workplace == nil ? (e.labelId ?? Store.noLabelKey) : nil))
        }
        for t in store.tasks {
            guard let image = t.imageId else { continue }
            out.append(AlbumPhoto(id: "t:" + t.id, imageId: image, date: t.startDate ?? t.dueDate,
                                  title: t.title, source: .task))
        }
        return sorted(out)
    }

    /// 共有カレンダーの写真。その共有カレンダーの中で作った予定だけ(自分や参加者が、自分の予定を共有に出したものは、
    /// 画像を共有しないので含めない)
    static func shared(_ events: [SharedEvent]) -> [AlbumPhoto] {
        let photos = events.compactMap { e -> AlbumPhoto? in
            guard e.isCalendarOwned, let image = e.imageId else { return nil }
            return AlbumPhoto(id: "s:" + e.id, imageId: image, date: e.placed && !e.startDate.isEmpty ? e.startDate : nil,
                              title: e.title, source: .event)
        }
        return sorted(photos)
    }

    /// 新しい日付が先。日付未定は最後。同じ日は、予定名の順
    static func sorted(_ photos: [AlbumPhoto]) -> [AlbumPhoto] {
        photos.sorted { a, b in
            switch (a.date, b.date) {
            case let (x?, y?) where x != y: return x > y
            case (nil, _?): return false
            case (_?, nil): return true
            default: return (a.title, a.id) < (b.title, b.id)
            }
        }
    }

    static func filtered(_ photos: [AlbumPhoto], by filter: AlbumFilter) -> [AlbumPhoto] {
        switch filter {
        case .all: return photos
        case .workplace(let id): return photos.filter { $0.workplaceId == id }
        case .label(let key): return photos.filter { $0.labelKey == key }
        case .tasks: return photos.filter { $0.source == .task }
        }
    }

    /// 月ごとに分ける(並びは、渡した順のまま)
    static func sections(_ photos: [AlbumPhoto]) -> [AlbumSection] {
        var out: [AlbumSection] = []
        var current: (id: String, photos: [AlbumPhoto])?
        func flush() {
            guard let c = current else { return }
            out.append(AlbumSection(id: c.id, title: sectionTitle(c.id), photos: c.photos))
        }
        for p in photos {
            let key = p.date.map { String($0.prefix(7)) } ?? ""
            if current?.id == key {
                current?.photos.append(p)
            } else {
                flush()
                current = (key, [p])
            }
        }
        flush()
        return out
    }

    private static func sectionTitle(_ key: String) -> String {
        guard !key.isEmpty else { return "日付未定" }
        let p = key.split(separator: "-").compactMap { Int($0) }
        return p.count == 2 ? "\(p[0])年\(p[1])月" : key
    }

    private static let weekdays = ["日", "月", "火", "水", "木", "金", "土"]

    /// マスに重ねる日付。"11/22(日)"
    static func shortDate(_ date: String) -> String {
        let d = Rules.ymd(date)
        return "\(d.month)/\(d.day)(\(weekdays[Rules.weekday(date)]))"
    }

    /// 大きく見るときの日付。"2026年11月22日(日)"
    static func longDate(_ date: String) -> String {
        let d = Rules.ymd(date)
        return "\(d.year)年\(d.month)月\(d.day)日(\(weekdays[Rules.weekday(date)]))"
    }
}
