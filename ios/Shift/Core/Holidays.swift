import Foundation
import Observation

@Observable
final class Holidays {
    private(set) var table: [String: String]
    @ObservationIgnored private var fetched: Set<String>
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "shift-holidays"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var t = BuiltinHolidays.table
        if let data = defaults.data(forKey: Self.key),
           let cached = try? JSONDecoder().decode([String: String].self, from: data) {
            t.merge(cached) { _, new in new }
        }
        table = t
        fetched = Set(t.keys.map { String($0.prefix(4)) })
    }

    func name(on ds: String) -> String? { table[ds] }

    /// 前年・当年・翌年を未取得なら holidays-jp から取得する。失敗しても内蔵テーブルで動く
    func load(around year: Int) async {
        for y in [year - 1, year, year + 1] {
            let k = String(y)
            guard !fetched.contains(k) else { continue }
            fetched.insert(k)
            guard let url = URL(string: "https://holidays-jp.github.io/api/v1/\(k)/date.json"),
                  let (data, res) = try? await URLSession.shared.data(from: url),
                  (res as? HTTPURLResponse)?.statusCode == 200,
                  let dict = try? JSONDecoder().decode([String: String].self, from: data) else { continue }
            table.merge(dict) { _, new in new }
            if let encoded = try? JSONEncoder().encode(table) { defaults.set(encoded, forKey: Self.key) }
        }
    }
}
