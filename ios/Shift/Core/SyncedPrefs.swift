import Foundation

/// アカウントに預ける、端末の設定(表示・給料・アラームのスヌーズ・名前とアバター・ウィジェットなど)。
/// UserDefaults の中の、決まったキーだけを、文字にして持ち運ぶ。型は、文字の頭の印で分ける
/// (s: 文字、b: 真偽、i: 整数、f: 小数、d: データ、a: 文字の配列)
enum SyncedPrefs {
    /// 預ける設定のキー。画面の位置や、開いている状態のようなものは入れない
    static let keys: [String] = [
        "startMonday", "appearance", "calendarBackground", "summaryOn", "payBasis",
        "conflictWarningOn", "conflictGapMinutes", "alarmSnoozeMinutes",
        "monthBarFontDelta", "weekBarFontDelta", "monthBarThickness", "monthBarOverflowScroll", "taskLinkDots",
        "widget-prefs-small", "widget-prefs-medium",
        "profile-name", "profile-avatar",
        "shared-color-overrides", "shared-overlay-ids", "shared-bar-time-modes",
    ]

    /// いまの端末の設定(値のあるキーだけ)
    static func read(_ d: UserDefaults) -> [String: String] {
        var out: [String: String] = [:]
        for k in keys {
            guard let v = d.object(forKey: k), let s = encode(v) else { continue }
            out[k] = s
        }
        return out
    }

    /// アカウントの設定を、この端末へ入れる。アカウントに無いキーは、この端末からも外す(初期値に戻る)
    static func write(_ prefs: [String: String], to d: UserDefaults) {
        let current = read(d)
        for k in keys where current[k] != prefs[k] {
            if let raw = prefs[k], let v = decode(raw) {
                d.set(v, forKey: k)
            } else {
                d.removeObject(forKey: k)
            }
        }
    }

    /// 端末の設定を、すべて初期値に戻す(ログアウトで、まっさらにするとき)
    static func reset(_ d: UserDefaults) {
        for k in keys { d.removeObject(forKey: k) }
    }

    private static func encode(_ v: Any) -> String? {
        switch v {
        case let s as String: return "s:" + s
        case let data as Data: return "d:" + data.base64EncodedString()
        case let list as [String]:
            guard let j = try? JSONEncoder().encode(list) else { return nil }
            return "a:" + String(decoding: j, as: UTF8.self)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return "b:" + (n.boolValue ? "1" : "0") }
            let t = String(cString: n.objCType)
            if t == "d" || t == "f" { return "f:" + String(n.doubleValue) }
            return "i:" + String(n.intValue)
        default: return nil
        }
    }

    private static func decode(_ raw: String) -> Any? {
        guard raw.count >= 2, raw[raw.index(after: raw.startIndex)] == ":" else { return nil }
        let body = String(raw.dropFirst(2))
        switch raw.first {
        case "s": return body
        case "b": return body == "1"
        case "i": return Int(body)
        case "f": return Double(body)
        case "d": return Data(base64Encoded: body)
        case "a": return try? JSONDecoder().decode([String].self, from: Data(body.utf8))
        default: return nil
        }
    }
}
