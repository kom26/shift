import Foundation
import Observation

struct ColorTotal: Identifiable {
    let color: String
    var title: String = ""
    var hours: Double
    var count: Int
    var id: String { color }
}

@Observable
final class Store {
    static let defaultColors = ["#6366f1", "#06b6d4", "#f59e0b", "#ec4899", "#10b981", "#f97316", "#8b5cf6", "#ef4444"]

    static var defaultFileURL: URL {
        let dir = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "events.json")
    }

    private(set) var events: [ShiftEvent] = []
    private(set) var checkedColors: Set<String>
    private(set) var customColors: [String]
    private(set) var workplaces: [Workplace]

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let defaults: UserDefaults
    private enum Keys {
        static let checked = "shift-checked-colors"
        static let custom = "shift-custom-colors"
        static let workplaces = "shift-workplaces"
    }

    init(fileURL: URL = Store.defaultFileURL, defaults: UserDefaults = .standard) {
        self.fileURL = fileURL
        self.defaults = defaults
        checkedColors = Set(defaults.stringArray(forKey: Keys.checked) ?? [])
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

    /// 配置済みで、色フィルタを通る予定(フィルタが空なら全色)
    var visibleEvents: [ShiftEvent] {
        events.filter { $0.placed && $0.startDate != nil && (checkedColors.isEmpty || checkedColors.contains($0.color)) }
    }

    var colorsInUse: [String] {
        var seen = Set<String>()
        return events.map(\.color).filter { seen.insert($0).inserted }
    }

    /// 開始日が from...to に入る予定を色ごとに合計する
    func totals(from: String, to: String) -> [ColorTotal] {
        var order: [String] = []
        var map: [String: ColorTotal] = [:]
        for ev in visibleEvents {
            guard let sd = ev.startDate, sd >= from, sd <= to,
                  let h = ev.effectiveHours, h > 0 else { continue }
            if map[ev.color] == nil {
                order.append(ev.color)
                map[ev.color] = ColorTotal(color: ev.color, title: ev.title, hours: 0, count: 0)
            }
            map[ev.color]!.hours += h
            map[ev.color]!.count += 1
        }
        return order.compactMap { map[$0] }
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

    func save(_ event: ShiftEvent) {
        if let i = events.firstIndex(where: { $0.id == event.id }) {
            events[i] = event
        } else {
            events.append(event)
        }
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

    /// 日付へ配置する。配置済みなら元の日数(終了日−開始日)を保つ
    func place(id: String, on date: String) {
        guard let i = events.firstIndex(where: { $0.id == id }) else { return }
        var e = events[i]
        let duration: Int
        if let sd = e.startDate, let ed = e.endDate { duration = Rules.daysBetween(sd, ed) } else { duration = 0 }
        let baseEnd = duration > 0 ? Rules.addDays(date, duration) : date
        e.startDate = date
        e.endDate = Rules.resolveEndDate(start: date, end: baseEnd, allDay: e.allDay, startTime: e.startTime, endTime: e.endTime)
        e.placed = true
        events[i] = e
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

    func toggleColor(_ color: String) {
        if checkedColors.contains(color) { checkedColors.remove(color) } else { checkedColors.insert(color) }
        defaults.set(Array(checkedColors), forKey: Keys.checked)
    }

    func clearColors() {
        checkedColors = []
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
