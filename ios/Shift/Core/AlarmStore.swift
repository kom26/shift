import Foundation

/// セットしたアラームの記録(AlarmKit 側の実体とは id で対応させる)
extension Store {
    static func alarmsURL(for eventsURL: URL) -> URL {
        let base = eventsURL.deletingPathExtension().lastPathComponent
        return eventsURL.deletingLastPathComponent().appending(path: "\(base)-alarms.json")
    }

    func persistAlarms() {
        guard let data = try? JSONEncoder().encode(alarmEntries) else { return }
        try? data.write(to: Self.alarmsURL(for: fileURL), options: .atomic)
        notifyChanged()
    }

    /// その日に鳴るアラームを、鳴る順に返す(予定一覧の上のチップと、カレンダーのベルに使う)
    func alarmEntries(on ds: String, calendar: Calendar = .current) -> [AlarmEntry] {
        guard let day = Rules.parse(ds) else { return [] }
        let start = calendar.startOfDay(for: day)
        return alarmEntries
            .filter { calendar.isDate(Date(timeIntervalSince1970: $0.fireTime), inSameDayAs: start) }
            .sorted { $0.fireTime < $1.fireTime }
    }

    /// その日に鳴るアラームの数。月表示・週表示のベルマーク用(2 個以上なら「+1」を添える)
    func alarmCount(on ds: String) -> Int { alarmEntries(on: ds).count }

    func hasAlarm(on ds: String) -> Bool { alarmCount(on: ds) > 0 }

    func alarmEntry(matching spec: AlarmPreset, on ds: String) -> AlarmEntry? {
        alarmEntries.first { $0.date == ds && $0.kind == spec.kind && $0.minutes == spec.minutes }
    }

    /// ds の日に鳴るアラームの時刻(0時からの分)。週表示の線用。基準日と別の日に鳴るものも含む
    func alarmFireMinutes(on ds: String, calendar: Calendar = .current) -> [Int] {
        guard let day = Rules.parse(ds) else { return [] }
        let start = calendar.startOfDay(for: day)
        return alarmEntries.compactMap { e in
            let t = Date(timeIntervalSince1970: e.fireTime)
            guard calendar.isDate(t, inSameDayAs: start) else { return nil }
            let c = calendar.dateComponents([.hour, .minute], from: t)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
    }

    func addAlarmEntry(_ entry: AlarmEntry) {
        alarmEntries.append(entry)
        persistAlarms()
    }

    /// 記録を、同じ id の新しい内容に入れ替える(時刻やスヌーズを直したとき)
    func updateAlarmEntry(_ entry: AlarmEntry) {
        guard let i = alarmEntries.firstIndex(where: { $0.id == entry.id }) else { return }
        alarmEntries[i] = entry
        persistAlarms()
    }

    func removeAlarmEntry(id: String) {
        alarmEntries.removeAll { $0.id == id }
        persistAlarms()
    }

    func updateAlarmFireTime(id: String, to fireTime: TimeInterval) {
        guard let i = alarmEntries.firstIndex(where: { $0.id == id }) else { return }
        alarmEntries[i].fireTime = fireTime
        persistAlarms()
    }

    /// 鳴る時刻を過ぎた記録を消す。消した記録を返す
    @discardableResult
    func pruneAlarmEntries(now: Date = Date()) -> [AlarmEntry] {
        let past = alarmEntries.filter { $0.fireTime <= now.timeIntervalSince1970 }
        guard !past.isEmpty else { return [] }
        alarmEntries.removeAll { $0.fireTime <= now.timeIntervalSince1970 }
        persistAlarms()
        return past
    }
}
