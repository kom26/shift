import FirebaseFunctions
import Foundation

/// シフト表のスクリーンショットから AI が読み取った、1 件分(1 日の 1 人ぶん)
struct ShiftLine: Identifiable, Equatable {
    /// yyyy-MM-dd
    var date: String
    /// "HH:mm"(24:00 もある)。時間のない行(終日)と休みは nil
    var start: String?
    var end: String?
    /// 「休」の日
    var off: Bool
    /// 表に書かれた名前(読み取る名前を指定したときだけ。何人か当てはまるときに、見分けるため)
    var name: String? = nil
    /// 読み取れなかった日(読み取った最初の日と最後の日のあいだで、抜けていた日)。確認の画面で、時間を入れてもらう
    var missing: Bool = false

    /// 同じ日でも、時間や名前が違えば、別の行
    var id: String { [date, start ?? "", end ?? "", off ? "off" : "", name ?? "", missing ? "missing" : ""].joined(separator: "|") }

    /// サーバーの返事(辞書の配列)から作る。形のおかしい行は捨てて、同じ日・同じ時間・同じ名前は 1 件にして、日付順に並べる
    static func parse(_ raw: Any?) -> [ShiftLine] {
        var byId: [String: ShiftLine] = [:]
        for item in (raw as? [[String: Any]]) ?? [] {
            guard let date = item["date"] as? String, Rules.parse(date) != nil, date.count == 10 else { continue }
            let off = item["off"] as? Bool ?? false
            let start = off ? nil : (item["start"] as? String).flatMap(Self.cleanTime)
            let end = off ? nil : (item["end"] as? String).flatMap(Self.cleanTime)
            // 時間が片方しか読めなかった行は、読み違いなので捨てる
            if !off, (start == nil) != (end == nil) { continue }
            let name = (item["name"] as? String).map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty || $0.count > 40 ? nil : $0 }
            let line = ShiftLine(date: date, start: start, end: end, off: off, name: name)
            byId[line.id] = line
        }
        return byId.values.sorted { ($0.date, $0.start ?? "", $0.name ?? "") < ($1.date, $1.start ?? "", $1.name ?? "") }
    }

    private static func cleanTime(_ s: String) -> String? {
        // 24:30〜31:00 などの夜勤もあるので、予定の終了時刻の上限(36:00)まで受ける
        guard let m = Rules.minutes(s.trimmingCharacters(in: .whitespaces)), m >= 0, m <= 36 * 60 else { return nil }
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}

/// 画像から AI が読み取った、開始・締切・タスク 1 件分
struct TaskLine: Identifiable, Equatable {
    var title: String
    /// yyyy-MM-dd。nil は無い
    var startDate: String?
    var startTime: String?
    var dueDate: String?
    var dueTime: String?
    /// タイトルの補足(見出しなど)。取り込むと、メモに入る
    var note: String = ""

    var id: String { [title, startDate ?? "", startTime ?? "", dueDate ?? "", dueTime ?? ""].joined(separator: "|") }

    /// サーバーの返事から作る。タイトルの無い行は捨てて、同じ内容は 1 件にする。順番は、サーバーが並べたまま
    static func parse(_ raw: Any?) -> [TaskLine] {
        var seen = Set<String>()
        var out: [TaskLine] = []
        for item in (raw as? [[String: Any]]) ?? [] {
            let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty, title.count <= 100 else { continue }
            func date(_ key: String) -> String? {
                guard let s = item[key] as? String, s.count == 10, Rules.parse(s) != nil else { return nil }
                return s
            }
            func time(_ key: String, on date: String?) -> String? {
                guard date != nil, let s = item[key] as? String,
                      let m = Rules.minutes(s.trimmingCharacters(in: .whitespaces)), m >= 0, m <= 24 * 60 else { return nil }
                return String(format: "%02d:%02d", m / 60, m % 60)
            }
            var start = date("startDate")
            let due = date("dueDate")
            if let s = start, let d = due, d < s { start = nil }
            let note = (item["note"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let line = TaskLine(title: title, startDate: start, startTime: time("startTime", on: start),
                                dueDate: due, dueTime: time("dueTime", on: due), note: note.count <= 200 ? note : "")
            if seen.insert(line.id).inserted { out.append(line) }
        }
        return out
    }

    /// 取り込む項目にする(色は、開始・締切の最初の色)
    func makeTask() -> TaskItem {
        TaskItem(id: UUID().uuidString, title: title, color: TaskItem.defaultColor,
                 startDate: startDate, startTime: startTime, dueDate: dueDate, dueTime: dueTime, done: false, memo: note)
    }
}

/// 読み取りに添える指定
struct ScreenshotReadOptions: Equatable {
    /// 複数の名前がある表で、読み取る名前(部分一致でよい)
    var name: String? = nil
    /// 写真に年月の表記がないときの、年月("YYYY-MM")
    var yearMonth: String? = nil
}

/// スクリーンショットを読み取る(テストでは差し替える)
protocol ScreenshotReading {
    /// 画像(JPEG)を 1〜5 枚まとめて送り、日付ごとの時間を返す
    func read(images: [Data]) async throws -> [ShiftLine]
    /// 名前や年月の指定つき
    func read(images: [Data], options: ScreenshotReadOptions) async throws -> [ShiftLine]
    /// 画像から、開始・締切・タスクを読み取る
    func readTasks(images: [Data], options: ScreenshotReadOptions) async throws -> [TaskLine]
}

extension ScreenshotReading {
    func read(images: [Data], options: ScreenshotReadOptions) async throws -> [ShiftLine] {
        try await read(images: images)
    }

    func readTasks(images: [Data], options: ScreenshotReadOptions) async throws -> [TaskLine] {
        throw ScreenshotReadError(message: "開始・締切の読み取りには、対応していません")
    }
}

struct ScreenshotReadError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Firebase の Cloud Functions(readShiftScreenshots)を呼ぶ。API キーはサーバーにだけあり、アプリには入っていない
struct FirebaseScreenshotReader: ScreenshotReading {
    func read(images: [Data]) async throws -> [ShiftLine] {
        try await read(images: images, options: ScreenshotReadOptions())
    }

    func read(images: [Data], options: ScreenshotReadOptions) async throws -> [ShiftLine] {
        ShiftLine.parse(try await call(images: images, options: options, kind: nil)["lines"])
    }

    func readTasks(images: [Data], options: ScreenshotReadOptions) async throws -> [TaskLine] {
        TaskLine.parse(try await call(images: images, options: options, kind: "tasks")["tasks"])
    }

    /// サーバーを呼ぶ。kind が tasks のときは開始・締切、なければシフト
    private func call(images: [Data], options: ScreenshotReadOptions, kind: String?) async throws -> [String: Any] {
        let callable = Functions.functions(region: "asia-northeast1").httpsCallable("readShiftScreenshots")
        callable.timeoutInterval = 120
        var payload: [String: Any] = ["images": images.map { $0.base64EncodedString() }]
        if let name = options.name { payload["name"] = name }
        if let yearMonth = options.yearMonth { payload["yearMonth"] = yearMonth }
        if let kind { payload["kind"] = kind }
        do {
            let result = try await callable.call(payload)
            guard let body = result.data as? [String: Any] else {
                throw ScreenshotReadError(message: "読み取り結果を受け取れませんでした")
            }
            return body
        } catch let error as ScreenshotReadError {
            throw error
        } catch {
            let e = error as NSError
            if e.domain == FunctionsErrorDomain, let code = FunctionsErrorCode(rawValue: e.code) {
                switch code {
                case .unauthenticated: throw ScreenshotReadError(message: "画像から追加するには、アカウント登録かログインが必要です")
                case .resourceExhausted, .invalidArgument, .internal:
                    // サーバーが、利用者に見せる言葉で返している
                    throw ScreenshotReadError(message: e.localizedDescription)
                default: break
                }
            }
            throw ScreenshotReadError(message: "読み取れませんでした。通信を確かめて、もう一度試してください")
        }
    }
}
