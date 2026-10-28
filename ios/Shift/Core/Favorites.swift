import Foundation

/// よく使う予定(日付なしのテンプレート)と、それを使ったスタンプ配置・自動候補
extension Store {
    static let favoritePrefix = "fav:"

    static func favoritesURL(for eventsURL: URL) -> URL {
        let base = eventsURL.deletingPathExtension().lastPathComponent
        return eventsURL.deletingLastPathComponent().appending(path: "\(base)-favorites.json")
    }

    private static let hiddenKey = "shift-hidden-suggestions"

    /// 同じ予定かを見分けるキー(タイトル・終日・時刻)
    static func favoriteKey(_ e: ShiftEvent) -> String {
        "\(e.title)|\(e.allDay)|\(e.startTime ?? "")|\(e.endTime ?? "")"
    }

    func persistFavorites() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        try? data.write(to: Self.favoritesURL(for: fileURL), options: .atomic)
        notifyChanged()
    }

    func isFavorite(_ event: ShiftEvent) -> Bool {
        let key = Self.favoriteKey(event)
        return favorites.contains { Self.favoriteKey($0) == key }
    }

    /// 日付・配置情報を外したテンプレートにする
    private func template(from event: ShiftEvent) -> ShiftEvent {
        var t = event
        t.startDate = nil
        t.endDate = nil
        t.placed = false
        return t
    }

    /// よく使う予定を保存する(同じIDなら更新、なければ末尾に追加)
    func saveFavorite(_ event: ShiftEvent) {
        let t = template(from: event)
        if let i = favorites.firstIndex(where: { $0.id == t.id }) {
            favorites[i] = t
        } else {
            favorites.append(t)
        }
        persistFavorites()
    }

    /// 既存の予定から登録する。同じ内容がすでにあれば何もしない
    @discardableResult
    func addFavorite(from event: ShiftEvent) -> Bool {
        guard !isFavorite(event) else { return false }
        var t = template(from: event)
        t.id = UUID().uuidString
        favorites.append(t)
        persistFavorites()
        return true
    }

    func removeFavorite(id: String) {
        favorites.removeAll { $0.id == id }
        persistFavorites()
    }

    func moveFavoriteToFront(id: String) {
        guard let i = favorites.firstIndex(where: { $0.id == id }), i > 0 else { return }
        favorites.insert(favorites.remove(at: i), at: 0)
        persistFavorites()
    }

    func favorite(id: String) -> ShiftEvent? { favorites.first { $0.id == id } }

    /// 職場フィルタ(nil=すべて、noWorkplaceKey=指定なし)で絞ったよく使う予定
    func favorites(workplaceFilter: String?) -> [ShiftEvent] {
        guard let f = workplaceFilter else { return favorites }
        return favorites.filter { (workplace(for: $0)?.id ?? Store.noWorkplaceKey) == f }
    }

    /// 日付に置いた新しい予定(テンプレートと同じ内容、新しいID)
    func stampedEvent(_ template: ShiftEvent, on date: String) -> ShiftEvent {
        var e = moved(template, on: date)
        e.id = UUID().uuidString
        return e
    }

    /// その日に同じ内容の配置済み予定があるか
    func stampedEvent(matching template: ShiftEvent, on date: String) -> ShiftEvent? {
        let key = Self.favoriteKey(template)
        return events.first { $0.placed && $0.startDate == date && Self.favoriteKey($0) == key }
    }

    enum StampResult { case placed, removed }

    /// スタンプモードのタップ。同じ日に同じ予定があれば削除、なければ配置する
    @discardableResult
    func stampToggle(favoriteId: String, on date: String) -> StampResult? {
        guard let t = favorite(id: favoriteId) else { return nil }
        if let existing = stampedEvent(matching: t, on: date) {
            delete(id: existing.id)
            return .removed
        }
        appendEvent(stampedEvent(t, on: date))
        return .placed
    }

    /// ドラッグでのコピー配置。常に新しい予定を足す
    func stampCopy(favoriteId: String, on date: String) {
        guard let t = favorite(id: favoriteId) else { return }
        appendEvent(stampedEvent(t, on: date))
    }

    /// 同じタイトル・時間で3回以上入れた予定の自動候補(登録済み・非表示済みは除く)
    func favoriteSuggestions(limit: Int = 3) -> [ShiftEvent] {
        var counts: [String: (count: Int, event: ShiftEvent)] = [:]
        for e in events where e.placed && !e.title.isEmpty {
            let key = Self.favoriteKey(e)
            let c = counts[key]?.count ?? 0
            counts[key] = (c + 1, e)
        }
        let existing = Set(favorites.map { Self.favoriteKey($0) })
        return counts
            .filter { $0.value.count >= 3 && !existing.contains($0.key) && !hiddenSuggestions.contains($0.key) }
            .sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
            .prefix(limit)
            .map { $0.value.event }
    }

    func hideSuggestion(_ event: ShiftEvent) {
        hiddenSuggestions.insert(Self.favoriteKey(event))
        defaults.set(Array(hiddenSuggestions), forKey: Self.hiddenKey)
        notifyChanged()
    }
}
