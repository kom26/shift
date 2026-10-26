import Foundation

/// アラームのひな形。「時刻」(毎回同じ時刻) か「シフトの○分前」
struct AlarmPreset: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case clock, beforeShift }

    var id: String = UUID().uuidString
    var kind: Kind
    /// clock: 0時からの分(例 6:30 → 390)。beforeShift: 開始の何分前か
    var minutes: Int

    /// バーに出す表記(例「6:30」「シフト3時間前」)
    var label: String {
        switch kind {
        case .clock:
            return String(format: "%d:%02d", minutes / 60, minutes % 60)
        case .beforeShift:
            let h = minutes / 60, m = minutes % 60
            if h == 0 { return "シフト\(m)分前" }
            return m == 0 ? "シフト\(h)時間前" : "シフト\(h)時間\(m)分前"
        }
    }
}

/// 実際にセットしたアラーム1件(AlarmKit の id と対応)
struct AlarmEntry: Codable, Identifiable, Equatable {
    /// AlarmKit に渡した UUID 文字列
    var id: String
    var kind: AlarmPreset.Kind
    /// AlarmPreset.minutes と同じ(時刻なら0時からの分、シフト前なら何分前か)
    var minutes: Int
    /// 基準になる日(時刻: かけた日 / シフト前: シフトのある日)
    var date: String
    /// 実際に鳴らす時刻(秒単位の Unix 時間)
    var fireTime: TimeInterval
}

enum AlarmMath {
    /// その日の0:00 から minutes 分後の日時(ローカル時刻)
    static func date(on ds: String, minutes: Int, calendar: Calendar = .current) -> Date? {
        guard let day = Rules.parse(ds) else { return nil }
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: minutes, to: start)
    }

    /// その日の時刻つき・配置済みの予定のうち、いちばん早い開始(0時からの分)。なければ nil
    static func earliestStartMinutes(on ds: String, events: [ShiftEvent]) -> Int? {
        events
            .filter { $0.placed && !$0.allDay && $0.startDate == ds }
            .compactMap { Rules.minutes($0.startTime) }
            .min()
    }

    /// アラームを鳴らす日時。beforeShift でその日に予定がなければ nil
    static func fireDate(preset: AlarmPreset, on ds: String, events: [ShiftEvent],
                         calendar: Calendar = .current) -> Date? {
        switch preset.kind {
        case .clock:
            return date(on: ds, minutes: preset.minutes, calendar: calendar)
        case .beforeShift:
            guard let s = earliestStartMinutes(on: ds, events: events) else { return nil }
            return date(on: ds, minutes: s - preset.minutes, calendar: calendar)
        }
    }
}
