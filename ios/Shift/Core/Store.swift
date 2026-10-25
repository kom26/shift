import Foundation
import Observation

struct ColorTotal: Identifiable {
    let color: String
    var title: String = ""
    var hours: Double
    var count: Int
    var pay: Double = 0
    /// グループキー: 職場ID、職場なしの予定は予定の色
    var key: String = ""
    var id: String { key }
}

@Observable
final class Store {
    // ラベンダー, ミント, ピーチ, バター, スカイ, ピンク
    /// 色相環12色(紫から開始)+茶+灰。パステル
    static let defaultColors = ["#bf8df2", "#f28de1", "#f28dae", "#f28d8d", "#f2bf8d", "#f2e18d", "#c8f28d", "#8df29d", "#8df2d9", "#8de1f2", "#8dbff2", "#8d8df2", "#cc9e76", "#bec1cc"]

    static var defaultFileURL: URL {
        let dir = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "events.json")
    }

    private(set) var events: [ShiftEvent] = []
    private(set) var checkedWorkplaces: Set<String>
    private(set) var customColors: [String]
    private(set) var workplaces: [Workplace]

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let defaults: UserDefaults
    private enum Keys {
        static let checked = "shift-checked-workplaces"
        static let custom = "shift-custom-colors"
        static let workplaces = "shift-workplaces"
    }

    init(fileURL: URL = Store.defaultFileURL, defaults: UserDefaults = .standard) {
        self.fileURL = fileURL
        self.defaults = defaults
        checkedWorkplaces = Set(defaults.stringArray(forKey: Keys.checked) ?? [])
        customColors = defaults.stringArray(forKey: Keys.custom) ?? []
        workplaces = defaults.data(forKey: Keys.workplaces)
            .flatMap { try? JSONDecoder().decode([Workplace].self, from: $0) } ?? []
        if let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder().decode([ShiftEvent].self, from: data) {
            events = list
        } else if FileManager.default.fileExists(atPath: fileURL.path) {
            // 読めないファイルは退避し、次の persist() で上書きされないようにする
            let base = fileURL.deletingPathExtension().lastPathComponent
            let dest = fileURL.deletingLastPathComponent()
                .appending(path: "\(base).corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: dest)
        }
    }

    // MARK: 参照

    /// 「指定なし」(職場に結びつかない予定)を表すフィルタ用の番兵ID
    static let noWorkplaceKey = ""

    /// 配置済みで、職場フィルタを通る予定(フィルタが空なら全て)
    var visibleEvents: [ShiftEvent] {
        events.filter {
            $0.placed && $0.startDate != nil
                && (checkedWorkplaces.isEmpty || checkedWorkplaces.contains(workplace(for: $0)?.id ?? Store.noWorkplaceKey))
        }
    }

    /// 開始日が from...to に入る予定を職場ごとに合計する(職場なしは色ごと)
    func totals(from: String, to: String, isHoliday: (String) -> Bool = { _ in false }, orderBy: [String]? = nil) -> [ColorTotal] {
        var order: [String] = []
        var map: [String: ColorTotal] = [:]
        for ev in visibleEvents {
            guard let sd = ev.startDate, sd >= from, sd <= to,
                  let h = ev.effectiveHours, h > 0 else { continue }
            let w = workplace(for: ev)
            let key = w?.id ?? ev.color
            if map[key] == nil {
                order.append(key)
                map[key] = ColorTotal(color: w?.color ?? ev.color, title: w?.name ?? ev.title,
                                      hours: 0, count: 0, key: key)
            }
            map[key]!.hours += h
            map[key]!.count += 1
            if let w, let p = PayCalculator.pay(event: ev, workplace: w, isHoliday: isHoliday(sd)) {
                map[key]!.pay += p.total
            }
        }
        let base = order.compactMap { map[$0] }
        // 時間の降順(同値は初出順を維持)。orderBy があればその並びを優先し、無いものは後ろへ
        let byHours = base.enumerated().sorted {
            $0.element.hours != $1.element.hours ? $0.element.hours > $1.element.hours : $0.offset < $1.offset
        }.map(\.element)
        guard let orderBy else { return byHours }
        let ranked = byHours.enumerated().map { (idx: orderBy.firstIndex(of: $0.element.key), pos: $0.offset, t: $0.element) }
        let inList = ranked.filter { $0.idx != nil }.sorted { $0.idx! < $1.idx! }
        let rest = ranked.filter { $0.idx == nil }
        return (inList + rest).map(\.t)
    }

    struct PaymentRow: Identifiable {
        let workplace: Workplace
        let start: String
        let end: String
        let amount: Double
        var id: String { workplace.id }
    }

    func hasPayday(on ds: String) -> Bool {
        workplaces.contains { PayCycle.isPayday(ds, workplace: $0) }
    }

    /// ds が給料日の職場ごとに、締め期間内の給与合計を返す(色フィルタは無視)
    func payments(onPayday ds: String, isHoliday: (String) -> Bool = { _ in false }) -> [PaymentRow] {
        workplaces.compactMap { w in
            guard let period = PayCycle.period(forPayday: ds, workplace: w) else { return nil }
            var amount = 0.0
            for ev in events where ev.placed {
                guard let sd = ev.startDate, sd >= period.start, sd <= period.end,
                      let ew = workplace(for: ev), ew.id == w.id,
                      let p = PayCalculator.pay(event: ev, workplace: w, isHoliday: isHoliday(sd)) else { continue }
                amount += p.total
            }
            return PaymentRow(workplace: w, start: period.start, end: period.end, amount: amount)
        }
    }

    /// workplaceId が一致する職場、なければタイトルが職場名と一致する職場
    func workplace(for event: ShiftEvent) -> Workplace? {
        if let id = event.workplaceId, let w = workplaces.first(where: { $0.id == id }) { return w }
        return workplaces.first(where: { $0.name == event.title })
    }

    /// 同じ内容で新IDのコピーを作る。配置済みなら最後の配置済みの直後、未配置なら末尾
    func duplicate(id: String) {
        guard let src = events.first(where: { $0.id == id }) else { return }
        var copy = src
        copy.id = UUID().uuidString
        var placed = events.filter(\.placed)
        var unplaced = events.filter { !$0.placed }
        if copy.placed { placed.append(copy) } else { unplaced.append(copy) }
        events = placed + unplaced
        persist()
    }


    // MARK: 変更

    /// 職場フィルタ中に、フィルタで隠れる予定が配置された(追加・編集・ドラッグ)ら、見えるようにフィルタを外す
    private func revealIfFiltered(_ event: ShiftEvent) {
        guard !checkedWorkplaces.isEmpty, event.placed, event.startDate != nil,
              !checkedWorkplaces.contains(workplace(for: event)?.id ?? Store.noWorkplaceKey) else { return }
        clearWorkplaceFilter()
    }

    func save(_ event: ShiftEvent) {
        if let i = events.firstIndex(where: { $0.id == event.id }) {
            events[i] = event
        } else {
            events.append(event)
        }
        revealIfFiltered(event)
        persist()
    }

    /// 編集内容を保存したうえで、同じ内容のコピーを別IDで追加する(Web版の「複製保存」)
    func saveAndDuplicate(_ event: ShiftEvent) {
        save(event)
        var copy = event
        copy.id = UUID().uuidString
        events.append(copy)
        persist()
    }

    func delete(id: String) {
        events.removeAll { $0.id == id }
        persist()
    }

    var unplacedEvents: [ShiftEvent] { events.filter { !$0.placed } }

    /// 日付へ配置した後の姿。配置済みなら元の日数(終了日−開始日)を保つ
    func moved(_ event: ShiftEvent, on date: String) -> ShiftEvent {
        var e = event
        let duration: Int
        if let sd = e.startDate, let ed = e.endDate { duration = Rules.daysBetween(sd, ed) } else { duration = 0 }
        let baseEnd = duration > 0 ? Rules.addDays(date, duration) : date
        e.startDate = date
        e.endDate = Rules.resolveEndDate(start: date, end: baseEnd, allDay: e.allDay, startTime: e.startTime, endTime: e.endTime)
        e.placed = true
        return e
    }

    /// ドラッグ中の予定を date に置いたときの姿(ハイライト用)。見つからなければ nil
    func dropPreview(id: String, on date: String) -> ShiftEvent? {
        guard let e = events.first(where: { $0.id == id }) else { return nil }
        return moved(e, on: date)
    }

    /// 日付へ配置する
    func place(id: String, on date: String) {
        guard let i = events.firstIndex(where: { $0.id == id }) else { return }
        events[i] = moved(events[i], on: date)
        revealIfFiltered(events[i])
        persist()
    }

    /// 未配置に戻し、未配置グループの末尾へ移す
    func unplace(id: String) {
        guard let i = events.firstIndex(where: { $0.id == id }) else { return }
        var e = events.remove(at: i)
        e.startDate = nil
        e.endDate = nil
        e.placed = false
        events = events.filter(\.placed) + events.filter { !$0.placed } + [e]
        persist()
    }

    func sortUnplaced() {
        events = events.filter(\.placed) + Rules.sortUnplaced(events.filter { !$0.placed })
        persist()
    }

    /// date を含む月に開始日がある配置済み予定を全て未配置に戻し、未配置を並び替える。戻した件数を返す
    @discardableResult
    func recallMonth(of date: String) -> Int {
        let b = Rules.monthBounds(of: date)
        var recalled: [ShiftEvent] = []
        var rest: [ShiftEvent] = []
        for ev in events {
            if ev.placed, let sd = ev.startDate, sd >= b.first, sd <= b.last {
                var e = ev
                e.startDate = nil
                e.endDate = nil
                e.placed = false
                recalled.append(e)
            } else {
                rest.append(ev)
            }
        }
        guard !recalled.isEmpty else { return 0 }
        events = rest.filter(\.placed) + Rules.sortUnplaced(rest.filter { !$0.placed } + recalled)
        persist()
        return recalled.count
    }

    func toggleWorkplaceFilter(_ id: String) {
        if checkedWorkplaces.contains(id) { checkedWorkplaces.remove(id) } else { checkedWorkplaces.insert(id) }
        defaults.set(Array(checkedWorkplaces), forKey: Keys.checked)
    }

    func clearWorkplaceFilter() {
        checkedWorkplaces = []
        defaults.set([String](), forKey: Keys.checked)
    }

    func rememberColor(_ color: String) {
        guard !Self.defaultColors.contains(color) else { return }
        customColors = Array(([color] + customColors.filter { $0 != color }).prefix(8))
        defaults.set(customColors, forKey: Keys.custom)
    }

    /// Web版 localStorage の予定JSON(配列)を読み込む。同じIDは上書き。失敗時は何も変更しない
    @discardableResult
    func importJSON(_ data: Data) throws -> Int {
        let list = try JSONDecoder().decode([ShiftEvent].self, from: data)
        for ev in list {
            if let i = events.firstIndex(where: { $0.id == ev.id }) { events[i] = ev } else { events.append(ev) }
        }
        persist()
        return list.count
    }

    // MARK: 職場

    func addWorkplace(name: String, color: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        workplaces.append(Workplace(id: UUID().uuidString, name: n, color: color))
        persistWorkplaces()
    }

    /// 詳細つきの職場を末尾へ追加する
    func addWorkplace(_ w: Workplace) {
        let n = w.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        var copy = w
        copy.name = n
        workplaces.append(copy)
        persistWorkplaces()
    }

    func updateWorkplace(id: String, name: String, color: String, applyToEvents: Bool) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, let i = workplaces.firstIndex(where: { $0.id == id }) else { return }
        let oldName = workplaces[i].name
        workplaces[i].name = n
        workplaces[i].color = color
        persistWorkplaces()
        if applyToEvents {
            for j in events.indices where events[j].title == oldName {
                events[j].title = n
                events[j].color = color
            }
            persist()
        }
    }

    /// 職場の詳細(時給・加給・休憩ルールなど)を同じIDの職場へ丸ごと反映する
    func updateWorkplaceDetails(_ w: Workplace) {
        guard let i = workplaces.firstIndex(where: { $0.id == w.id }) else { return }
        workplaces[i] = w
        persistWorkplaces()
    }

    func deleteWorkplace(id: String) {
        workplaces.removeAll { $0.id == id }
        persistWorkplaces()
    }

    func moveWorkplaces(from source: IndexSet, to destination: Int) {
        let moving = source.sorted().map { workplaces[$0] }
        let before = source.filter { $0 < destination }.count
        var rest = workplaces
        for i in source.sorted(by: >) { rest.remove(at: i) }
        rest.insert(contentsOf: moving, at: destination - before)
        workplaces = rest
        persistWorkplaces()
    }

    func eventCount(matchingTitle name: String) -> Int {
        events.filter { $0.title == name }.count
    }

    private func persistWorkplaces() {
        if let data = try? JSONEncoder().encode(workplaces) { defaults.set(data, forKey: Keys.workplaces) }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
