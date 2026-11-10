import Foundation

/// 開始・締切・タスク。予定とは別の入れ物で、開始日(その日から)と締切日(その日まで)のどちらか、両方、どちらも持たないもの(タスク)がある。
/// 時刻は、開始・締切のそれぞれに、あってもなくてもよい
struct TaskItem: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var color: String
    var startDate: String?
    /// "HH:mm"。nil は時刻なし
    var startTime: String?
    var dueDate: String?
    var dueTime: String?
    var done: Bool
    /// メモ。画像から取り込んだときの、タイトルの補足もここに入る
    var memo: String = ""
    /// 付けた URL と、画像(この端末の `AttachmentStore` に入っている名前)。nil は無い
    var url: String? = nil
    var imageId: String? = nil

    /// 最初に選ばれている色。カスタム色の並びの、赤(3 行目・色相 4°の列)。ウィジェットでも使う Core なので、画面の部品は参照せず、値で持つ
    static let defaultColor = "#df3226"

    static func new(startDate: String? = nil, dueDate: String? = nil) -> TaskItem {
        TaskItem(id: UUID().uuidString, title: "", color: defaultColor,
                 startDate: startDate, startTime: nil, dueDate: dueDate, dueTime: nil, done: false)
    }

    /// 締切が開始より前にならないようにする。前のときは、締切を開始の日に合わせる
    static func orderedDates(start: String?, due: String?) -> (start: String?, due: String?) {
        guard let s = start, let d = due, d < s else { return (start, due) }
        return (s, s)
    }

    var hasStart: Bool { startDate != nil }
    var hasDue: Bool { dueDate != nil }
    /// 開始も締切もない「タスク」
    var isPlain: Bool { !hasStart && !hasDue }

    enum CodingKeys: String, CodingKey {
        case id, title, color, startDate, startTime, dueDate, dueTime, done, memo, url, imageId
    }

    init(id: String, title: String, color: String, startDate: String?, startTime: String?,
         dueDate: String?, dueTime: String?, done: Bool, memo: String = "", url: String? = nil, imageId: String? = nil) {
        self.memo = memo
        self.url = url
        self.imageId = imageId
        self.id = id
        self.title = title
        self.color = color
        self.startDate = startDate
        self.startTime = startTime
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.done = done
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? TaskItem.defaultColor
        startDate = try c.decodeIfPresent(String.self, forKey: .startDate).nonEmpty
        startTime = try c.decodeIfPresent(String.self, forKey: .startTime).nonEmpty
        dueDate = try c.decodeIfPresent(String.self, forKey: .dueDate).nonEmpty
        dueTime = try c.decodeIfPresent(String.self, forKey: .dueTime).nonEmpty
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        memo = try c.decodeIfPresent(String.self, forKey: .memo) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url).nonEmpty
        imageId = try c.decodeIfPresent(String.self, forKey: .imageId).nonEmpty
    }
}

/// カレンダーに出す「開始」「締切」の印が、どの項目のどちら側か
struct TaskMarker: Equatable {
    let taskId: String
    let isStart: Bool
    /// 開始から締切までを 1 本につないだ印(月表示。両端がタグで、間は点線)
    var isLink = false
}

extension ShiftEvent {
    static let taskStartSource = "task-start"
    static let taskDueSource = "task-due"
    static let taskLinkSource = "task-link"

    /// 開始・締切の印として作った見かけの予定か(カレンダーの行の詰め方を、予定と同じにするために使う)
    var taskMarker: TaskMarker? {
        guard source == Self.taskStartSource || source == Self.taskDueSource || source == Self.taskLinkSource else { return nil }
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "task" else { return nil }
        return TaskMarker(taskId: String(parts[1]), isStart: source != Self.taskDueSource, isLink: source == Self.taskLinkSource)
    }
}

/// 予定一覧と、管理画面に出す 1 行(開始と締切の両方を持つ項目は、2 行になる)
struct TaskRow: Identifiable, Equatable {
    let task: TaskItem
    /// nil は、開始も締切もない「タスク」
    let isStart: Bool?
    var id: String { task.id + (isStart == nil ? "" : (isStart! ? ":start" : ":due")) }

    var date: String? { isStart == true ? task.startDate : (isStart == false ? task.dueDate : nil) }
    var time: String? { isStart == true ? task.startTime : (isStart == false ? task.dueTime : nil) }
    /// 時刻の場所に出す文字(時刻があれば時刻、なければ「開始」「締切」)
    var timeText: String { time ?? (isStart == true ? "開始" : "締切") }
}

extension Store {
    static func tasksURL(for eventsURL: URL) -> URL {
        let base = eventsURL.deletingPathExtension().lastPathComponent
        return eventsURL.deletingLastPathComponent().appending(path: "\(base)-tasks.json")
    }

    func persistTasks() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        try? data.write(to: Self.tasksURL(for: fileURL), options: .atomic)
        notifyChanged()
    }

    func loadTasks() {
        if let data = try? Data(contentsOf: Self.tasksURL(for: fileURL)),
           let list = try? JSONDecoder().decode([TaskItem].self, from: data) {
            tasks = list
        }
    }

    func task(id: String) -> TaskItem? { tasks.first { $0.id == id } }

    func saveTask(_ t: TaskItem) {
        if let i = tasks.firstIndex(where: { $0.id == t.id }) { tasks[i] = t } else { tasks.append(t) }
        persistTasks()
    }

    func deleteTask(id: String) {
        tasks.removeAll { $0.id == id }
        persistTasks()
    }

    /// 開始か締切の、片方の日だけを動かす。開始が締切より後ろになるときは、もう片方も、同じ日まで動かす
    func moveTask(id: String, isStart: Bool, to date: String) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        if isStart {
            tasks[i].startDate = date
            if let d = tasks[i].dueDate, d < date { tasks[i].dueDate = date }
        } else {
            tasks[i].dueDate = date
            if let s = tasks[i].startDate, s > date { tasks[i].startDate = date }
        }
        persistTasks()
    }

    func toggleTaskDone(id: String) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].done.toggle()
        persistTasks()
    }

    /// カレンダーに出す開始・締切の印。チェックを付けたものは出さない。
    /// 月表示と、週表示の終日の場所には、時刻の有無にかかわらず出す(週表示の時刻つきは線なので、timeless で分ける)
    func taskMarkers(timelessOnly: Bool = false, linked: Bool = false) -> [ShiftEvent] {
        var list: [ShiftEvent] = []
        for t in tasks where !t.done {
            // 月表示: 開始と締切が別の日なら、1 本につなぐ(間は点線)
            if linked, let s = t.startDate, let d = t.dueDate, s < d {
                list.append(ShiftEvent(id: "task:\(t.id):link", title: t.title, memo: "", color: t.color,
                                       startDate: s, endDate: d, placed: true, allDay: true,
                                       startTime: nil, endTime: nil, workHours: nil, source: ShiftEvent.taskLinkSource))
                continue
            }
            if let d = t.startDate, !timelessOnly || t.startTime == nil {
                list.append(marker(t, date: d, time: t.startTime, isStart: true))
            }
            if let d = t.dueDate, !timelessOnly || t.dueTime == nil {
                list.append(marker(t, date: d, time: t.dueTime, isStart: false))
            }
        }
        return list.sorted { ($0.startDate ?? "", $0.startTime ?? "") < ($1.startDate ?? "", $1.startTime ?? "") }
    }

    private func marker(_ t: TaskItem, date: String, time: String?, isStart: Bool) -> ShiftEvent {
        ShiftEvent(id: "task:\(t.id):\(isStart ? "start" : "due")", title: t.title, memo: "", color: t.color,
                   startDate: date, endDate: date, placed: true, allDay: time == nil,
                   startTime: time, endTime: nil, workHours: nil,
                   source: isStart ? ShiftEvent.taskStartSource : ShiftEvent.taskDueSource)
    }

    /// 週表示の線: その日の、時刻つきの開始・締切(分で、0〜1439)
    func taskLines(on ds: String) -> [(minutes: Int, isStart: Bool, task: TaskItem)] {
        var list: [(Int, Bool, TaskItem)] = []
        for t in tasks where !t.done {
            if t.startDate == ds, let m = Self.minutes(t.startTime) { list.append((m, true, t)) }
            if t.dueDate == ds, let m = Self.minutes(t.dueTime) { list.append((m, false, t)) }
        }
        return list.sorted { $0.0 < $1.0 }.map { (minutes: $0.0, isStart: $0.1, task: $0.2) }
    }

    private static func minutes(_ time: String?) -> Int? {
        guard let time else { return nil }
        let p = time.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return nil }
        return min(1439, p[0] * 60 + p[1])
    }

    /// その日の開始・締切の行(チェックを付けたものも、取消線つきで残す)。時刻のあるものを先に、時刻順
    func taskRows(on ds: String) -> [TaskRow] {
        var rows: [TaskRow] = []
        for t in tasks {
            if t.startDate == ds { rows.append(TaskRow(task: t, isStart: true)) }
            if t.dueDate == ds { rows.append(TaskRow(task: t, isStart: false)) }
        }
        return rows.sorted { a, b in
            switch (a.time, b.time) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            default: return false
            }
        }
    }

    /// 管理画面のタブごとの行。日付の昇順(同じ日は時刻順)でまとめる。タスクは、追加した順
    func taskRows(kind: TaskKind) -> [TaskRow] {
        switch kind {
        case .plain:
            return tasks.filter(\.isPlain).map { TaskRow(task: $0, isStart: nil) }
        case .start:
            return tasks.filter(\.hasStart).map { TaskRow(task: $0, isStart: true) }.sorted(by: Self.byDate)
        case .due:
            return tasks.filter(\.hasDue).map { TaskRow(task: $0, isStart: false) }.sorted(by: Self.byDate)
        }
    }

    private static func byDate(_ a: TaskRow, _ b: TaskRow) -> Bool {
        ((a.date ?? ""), (a.time ?? "99:99")) < ((b.date ?? ""), (b.time ?? "99:99"))
    }

    /// 管理画面のタブのバッジ(チェックを付けていない件数)
    func openTaskCount(kind: TaskKind) -> Int {
        taskRows(kind: kind).filter { !$0.task.done }.count
    }
}

enum TaskKind: String, CaseIterable, Identifiable {
    case plain, start, due
    var id: String { rawValue }
    var title: String {
        switch self {
        case .plain: return "タスク"
        case .start: return "開始"
        case .due: return "締切"
        }
    }
}
