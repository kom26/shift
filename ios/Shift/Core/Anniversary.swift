import Foundation

/// 記念日・誕生日。人の名前や年齢とは限らない(記念日は毎年・毎月を選べる)
struct Anniversary: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case birthday, anniversary }
    enum Icon: String, Codable, CaseIterable {
        case cake, toast, heart
        var asset: String {
            switch self {
            case .cake: return "AnnivCake"
            case .toast: return "AnnivToast"
            case .heart: return "AnnivHeart"
            }
        }
        /// SF Symbols での近い表し方(ウィジェットはアプリと同じ画像 asset を使う)
        var symbolName: String {
            switch self {
            case .cake: return "birthday.cake.fill"
            case .toast: return "wineglass.fill"
            case .heart: return "heart.fill"
            }
        }
        var label: String {
            switch self {
            case .cake: return "ケーキ"
            case .toast: return "乾杯"
            case .heart: return "ハート"
            }
        }
    }

    var id: String = UUID().uuidString
    var name: String = ""
    var kind: Kind = .birthday
    /// 年が分からないときは nil
    var year: Int? = nil
    var month: Int = 1
    var day: Int = 1
    /// 記念日だけ。true なら毎月(誕生日は常に毎年)
    var monthly: Bool = false
    var icon: Icon = .cake
    var color: String = "#f28d8d"
    var memo: String = ""
    /// 自分の誕生日(アカウント設定で決めたもの)。日付と名前は、アカウント設定からだけ変えられる(アイコンと色は、ここで変えられる)
    var isMine: Bool? = nil

    var isAccountBirthday: Bool { isMine == true }

    var isMonthly: Bool { kind == .anniversary && monthly }

    private static func daysIn(year: Int, month: Int) -> Int {
        let cal = Calendar(identifier: .gregorian)
        let d = cal.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        return cal.range(of: .day, in: .month, for: d)?.count ?? 31
    }

    /// その月の記念日の日(2/29 や 31日が無い月は月末に寄せる)
    private func dayIn(year: Int, month m: Int) -> Int {
        min(day, Self.daysIn(year: year, month: m))
    }

    /// ds がこの記念日にあたる日か
    func occurs(on ds: String) -> Bool {
        let p = Rules.ymd(ds)
        if let y = year, p.year < y { return false }
        if isMonthly {
            if let y = year, p.year == y, p.month < month { return false }
            return p.day == dayIn(year: p.year, month: p.month)
        }
        return p.month == month && p.day == dayIn(year: p.year, month: p.month)
    }

    /// 生年月日(年が分からないときは月日だけ)
    var dateText: String {
        let md = "\(month)月\(day)日"
        if isMonthly { return "毎月\(day)日" }
        return year.map { "\($0)年" + md } ?? md
    }

    /// asOf 時点までの経過(誕生日は「◯歳」、毎年の記念日は「◯周年」、毎月は「◯年◯ヶ月」)。年が不明なら nil
    func elapsedText(asOf ds: String) -> String? {
        guard let y = year else { return nil }
        let p = Rules.ymd(ds)
        if isMonthly {
            var months = (p.year - y) * 12 + (p.month - month)
            if p.day < dayIn(year: p.year, month: p.month) { months -= 1 }
            guard months >= 0 else { return nil }
            let yy = months / 12, mm = months % 12
            if yy == 0 { return "\(mm)ヶ月" }
            return mm == 0 ? "\(yy)年" : "\(yy)年\(mm)ヶ月"
        }
        var n = p.year - y
        if (p.month, p.day) < (month, dayIn(year: p.year, month: month)) { n -= 1 }
        guard n >= 0 else { return nil }
        return kind == .birthday ? "\(n)歳" : "\(n)周年"
    }
}

extension Store {
    static func anniversariesURL(for eventsURL: URL) -> URL {
        let base = eventsURL.deletingPathExtension().lastPathComponent
        return eventsURL.deletingLastPathComponent().appending(path: "\(base)-anniversaries.json")
    }

    func persistAnniversaries() {
        guard let data = try? JSONEncoder().encode(anniversaries) else { return }
        try? data.write(to: Self.anniversariesURL(for: fileURL), options: .atomic)
        notifyChanged()
    }

    func loadAnniversaries() {
        if let data = try? Data(contentsOf: Self.anniversariesURL(for: fileURL)),
           let list = try? JSONDecoder().decode([Anniversary].self, from: data) {
            anniversaries = list
        }
    }

    func saveAnniversary(_ a: Anniversary) {
        if let i = anniversaries.firstIndex(where: { $0.id == a.id }) {
            anniversaries[i] = a
        } else {
            anniversaries.append(a)
        }
        persistAnniversaries()
    }

    func deleteAnniversary(id: String) {
        anniversaries.removeAll { $0.id == id }
        persistAnniversaries()
    }

    func anniversaries(on ds: String) -> [Anniversary] {
        anniversaries.filter { $0.occurs(on: ds) }
    }

    /// アカウント設定で決めた、自分の誕生日
    var myBirthday: Anniversary? { anniversaries.first { $0.isAccountBirthday } }

    /// 自分の誕生日を、誕生日・記念日に入れる。すでにあれば、名前と日付だけ直す(アイコンと色は、そのまま)
    func setMyBirthday(name: String, year: Int?, month: Int, day: Int) {
        var a = myBirthday ?? Anniversary()
        a.isMine = true
        a.kind = .birthday
        a.monthly = false
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        a.name = trimmed.isEmpty ? "自分の誕生日" : trimmed + "の誕生日"
        a.year = year
        a.month = month
        a.day = day
        saveAnniversary(a)
    }

    /// アカウント設定で、誕生日の登録をやめたとき
    func clearMyBirthday() {
        if let a = myBirthday { deleteAnniversary(id: a.id) }
    }
}
