import FirebaseFunctions
import Foundation

/// シフト表のスクリーンショットから AI が読み取った、1 日分
struct ShiftLine: Identifiable, Equatable {
    /// yyyy-MM-dd
    var date: String
    /// "HH:mm"(24:00 もある)。時間のない行(終日)と休みは nil
    var start: String?
    var end: String?
    /// 「休」の日
    var off: Bool

    var id: String { date }

    /// サーバーの返事(辞書の配列)から作る。形のおかしい行は捨てて、同じ日は 1 件にして、日付順に並べる
    static func parse(_ raw: Any?) -> [ShiftLine] {
        var byDate: [String: ShiftLine] = [:]
        for item in (raw as? [[String: Any]]) ?? [] {
            guard let date = item["date"] as? String, Rules.parse(date) != nil, date.count == 10 else { continue }
            let off = item["off"] as? Bool ?? false
            let start = off ? nil : (item["start"] as? String).flatMap(Self.cleanTime)
            let end = off ? nil : (item["end"] as? String).flatMap(Self.cleanTime)
            // 時間が片方しか読めなかった行は、読み違いなので捨てる
            if !off, (start == nil) != (end == nil) { continue }
            byDate[date] = ShiftLine(date: date, start: start, end: end, off: off)
        }
        return byDate.values.sorted { $0.date < $1.date }
    }

    private static func cleanTime(_ s: String) -> String? {
        guard let m = Rules.minutes(s.trimmingCharacters(in: .whitespaces)), m >= 0, m <= 30 * 60 + 59 else { return nil }
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}

/// スクリーンショットを読み取る(テストでは差し替える)
protocol ScreenshotReading {
    /// 画像(JPEG)を 1〜5 枚まとめて送り、日付ごとの時間を返す
    func read(images: [Data]) async throws -> [ShiftLine]
}

struct ScreenshotReadError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Firebase の Cloud Functions(readShiftScreenshots)を呼ぶ。API キーはサーバーにだけあり、アプリには入っていない
struct FirebaseScreenshotReader: ScreenshotReading {
    func read(images: [Data]) async throws -> [ShiftLine] {
        let callable = Functions.functions(region: "asia-northeast1").httpsCallable("readShiftScreenshots")
        callable.timeoutInterval = 120
        do {
            let result = try await callable.call(["images": images.map { $0.base64EncodedString() }])
            guard let body = result.data as? [String: Any] else {
                throw ScreenshotReadError(message: "読み取り結果を受け取れませんでした")
            }
            return ShiftLine.parse(body["lines"])
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
