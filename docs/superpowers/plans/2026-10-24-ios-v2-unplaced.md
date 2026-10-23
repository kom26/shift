# シフト管理 iOS v2(未配置エリアとドラッグ配置) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Web版の主な使い方である「未配置の予定を日付へドラッグして配置する」操作を、iOSアプリで再現する。

**Architecture:** 配置・戻す・並び替え・回収は `Store` の純粋なロジックとして実装し、テストする。UIは `draggable` / `dropDestination` で結線する。データモデルは変更しない。

**Tech Stack:** Swift 5 モード、SwiftUI(iOS 17)、Swift Testing。外部ライブラリなし。

## Global Constraints

設計書 `docs/superpowers/specs/2026-10-24-ios-v2-unplaced-design.md` の内容。

- iOS 17+、SwiftUI、外部ライブラリなし。データモデル(`ShiftEvent`)は変更しない
- Web版の挙動を正とする(参照: `/c/tmp/shift_ro/index.html` の `sortUnplaced`、`handleDropOnCalendar`、`handleDropOnUnplaced`、`handleRecallMonth`)
- 配列の並びは「配置済み → 未配置」を保つ
- 配置: 配置済みなら元の日数(終了日−開始日)を保ち、終了日は `Rules.resolveEndDate` で確定する
- v2に含めない: バーのリサイズ、未配置内の手動並べ替え、複製ドラッグ、一括取り込み、ウィジェット

## 検証の方式

Swift ツールチェーンはローカルにない。コンパイルとテストは Codemagic(`Shift iOS test`)でのみ実行できる。各タスクはテストを先に書き、赤→緑の確認は Task 3 の後の CI でまとめて行う。`git push` は `feat/ios-swiftui` へのみ許可されている。

---

### Task 1: Rules と Store の配置ロジック(TDD)

**Files:**
- Modify: `ios/Shift/Core/Rules.swift`(`Rules` enum の中に追加)
- Modify: `ios/Shift/Core/Store.swift`(`Store` class の中に追加)
- Create: `ios/ShiftTests/StoreUnplacedTests.swift`

**Interfaces:**
- Consumes: `ShiftEvent`、`Rules.addDays / resolveEndDate / monthBounds / effectiveHours`、`Store.save / persist`、テスト用 `ev(...)`(`ios/ShiftTests/Fixtures.swift`)
- Produces:
  - `Rules.daysBetween(_ a: String, _ b: String) -> Int`
  - `Rules.sortUnplaced(_ evs: [ShiftEvent]) -> [ShiftEvent]`
  - `Store.unplacedEvents: [ShiftEvent]`
  - `Store.place(id: String, on date: String)`
  - `Store.unplace(id: String)`
  - `Store.sortUnplaced()`
  - `Store.recallMonth(of date: String) -> Int`(`@discardableResult`、戻した件数)

- [ ] **Step 1: 失敗するテストを書く**

`ios/ShiftTests/StoreUnplacedTests.swift`:

```swift
import Foundation
import Testing
@testable import Shift

struct StoreUnplacedTests {
    private func make() -> Store {
        let name = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).json")
        return Store(fileURL: url, defaults: UserDefaults(suiteName: name)!)
    }

    @Test func daysBetween() {
        #expect(Rules.daysBetween("2026-10-20", "2026-10-22") == 2)
        #expect(Rules.daysBetween("2026-10-30", "2026-11-02") == 3)
        #expect(Rules.daysBetween("2026-10-20", "2026-10-20") == 0)
    }

    @Test func placeUnplacedEventSetsDatesAndPlaced() {
        let store = make()
        store.save(ev("u", nil, placed: false))
        store.place(id: "u", on: "2026-10-24")
        let e = store.events[0]
        #expect(e.placed)
        #expect(e.startDate == "2026-10-24")
        #expect(e.endDate == "2026-10-24")
    }

    @Test func placeKeepsMultiDayDuration() {
        let store = make()
        store.save(ev("a", "2026-10-20", "2026-10-22"))
        store.place(id: "a", on: "2026-10-25")
        #expect(store.events[0].startDate == "2026-10-25")
        #expect(store.events[0].endDate == "2026-10-27")
    }

    @Test func placeOvernightEventEndsNextDay() {
        let store = make()
        store.save(ev("u", nil, placed: false, allDay: false, st: "22:00", et: "06:00"))
        store.place(id: "u", on: "2026-10-24")
        #expect(store.events[0].endDate == "2026-10-25")
    }

    @Test func placeUnknownIdIsIgnored() {
        let store = make()
        store.save(ev("a", "2026-10-20"))
        store.place(id: "nope", on: "2026-10-24")
        #expect(store.events.map(\.id) == ["a"])
        #expect(store.events[0].startDate == "2026-10-20")
    }

    @Test func unplaceClearsDatesAndMovesToEndOfUnplaced() {
        let store = make()
        store.save(ev("a", "2026-10-20"))
        store.save(ev("u1", nil, placed: false))
        store.save(ev("b", "2026-10-21"))
        store.unplace(id: "a")
        #expect(store.events.map(\.id) == ["b", "u1", "a"])
        let a = store.events[2]
        #expect(!a.placed)
        #expect(a.startDate == nil)
        #expect(a.endDate == nil)
        #expect(store.unplacedEvents.map(\.id) == ["u1", "a"])
    }

    @Test func sortUnplacedOrdersByStartTimeThenHoursWithAllDayLast() {
        let store = make()
        store.save(ev("p", "2026-10-20"))
        store.save(ev("a", nil, placed: false))
        store.save(ev("b", nil, placed: false, allDay: false, st: "15:00", et: "23:00"))
        store.save(ev("c", nil, placed: false, allDay: false, st: "07:00", et: "15:00"))
        store.save(ev("d", nil, placed: false, allDay: false, st: "15:00", et: "19:00"))
        store.sortUnplaced()
        #expect(store.events.map(\.id) == ["p", "c", "d", "b", "a"])
    }

    @Test func recallMonthMovesOnlyThatMonthAndSorts() {
        let store = make()
        store.save(ev("x", "2026-10-10", allDay: false, st: "09:00", et: "18:00"))
        store.save(ev("y", "2026-11-02"))
        store.save(ev("u", nil, placed: false, allDay: false, st: "20:00", et: "23:00"))
        let n = store.recallMonth(of: "2026-10-15")
        #expect(n == 1)
        #expect(store.events.map(\.id) == ["y", "x", "u"])
        #expect(store.events[1].placed == false)
        #expect(store.events[1].startDate == nil)
    }

    @Test func recallMonthWithNothingToRecallReturnsZero() {
        let store = make()
        store.save(ev("y", "2026-11-02"))
        #expect(store.recallMonth(of: "2026-10-15") == 0)
        #expect(store.events.map(\.id) == ["y"])
    }

    @Test func unplacedChangesPersist() {
        let name = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).json")
        let defaults = UserDefaults(suiteName: name)!
        let store = Store(fileURL: url, defaults: defaults)
        store.save(ev("a", "2026-10-20"))
        store.unplace(id: "a")
        let reloaded = Store(fileURL: url, defaults: defaults)
        #expect(reloaded.events[0].placed == false)
    }
}
```

- [ ] **Step 2: Rules に追加する**

`ios/Shift/Core/Rules.swift` の `enum Rules { ... }` 内、`dateInRange` の直後に追加:

```swift
    static func daysBetween(_ a: String, _ b: String) -> Int {
        guard let da = parse(a), let db = parse(b) else { return 0 }
        return cal.dateComponents([.day], from: da, to: db).day ?? 0
    }

    /// 開始時刻の昇順(終日・時刻なしは末尾)、同時刻は勤務時間の短い順、同値は元の順(Web版 sortUnplaced 相当)
    static func sortUnplaced(_ evs: [ShiftEvent]) -> [ShiftEvent] {
        func key(_ e: ShiftEvent) -> String { e.allDay ? "99:99" : (e.startTime ?? "99:99") }
        func hours(_ e: ShiftEvent) -> Double { e.effectiveHours ?? 999 }
        return evs.enumerated().sorted { a, b in
            let ka = key(a.element), kb = key(b.element)
            if ka != kb { return ka < kb }
            let ha = hours(a.element), hb = hours(b.element)
            if ha != hb { return ha < hb }
            return a.offset < b.offset
        }.map(\.element)
    }
```

- [ ] **Step 3: Store に追加する**

`ios/Shift/Core/Store.swift` の `Store` class 内、`delete(id:)` の直後に追加(`persist()` は同じクラスの private メソッド):

```swift
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
```

- [ ] **Step 4: コミットする**

```bash
cd /c/tmp/shift_ro
git add ios
git commit -m "feat(ios): 未配置の配置・戻す・並び替え・月回収のロジックを追加

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: 未配置エリアのビュー

**Files:**
- Create: `ios/Shift/Views/Sidebar/FlowLayout.swift`
- Create: `ios/Shift/Views/Sidebar/UnplacedArea.swift`

**Interfaces:**
- Consumes: `Store.unplacedEvents / sortUnplaced / recallMonth(of:) / unplace(id:)`、`Rules.timeLabel / ymd`、`Color(hex:)`、`Theme.accent`
- Produces:
  - `FlowLayout: Layout`(子ビューを折り返して並べる)
  - `UnplacedArea(anchor: String, onSelectEvent: (ShiftEvent) -> Void)` — 画面下に置く。チップは `draggable(ev.id)`、「未配置に戻す」ゾーンは `dropDestination(for: String.self)` で受けて `store.unplace` を呼ぶ

- [ ] **Step 1: FlowLayout を書く**

`ios/Shift/Views/Sidebar/FlowLayout.swift`:

```swift
import SwiftUI

/// 子ビューを幅に合わせて折り返しながら並べる
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > maxW {
                y += rowH + spacing
                x = 0
                rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + sz.width > bounds.maxX {
                y += rowH + spacing
                x = bounds.minX
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}
```

- [ ] **Step 2: UnplacedArea を書く**

`ios/Shift/Views/Sidebar/UnplacedArea.swift`:

```swift
import SwiftUI
import UIKit

struct UnplacedArea: View {
    @Environment(Store.self) private var store
    let anchor: String
    let onSelectEvent: (ShiftEvent) -> Void

    @AppStorage("unplacedCollapsed") private var collapsed = false
    @State private var confirmRecall = false
    @State private var backTargeted = false

    private var monthLabel: String {
        let p = Rules.ymd(anchor)
        return String(format: "%04d/%02d", p.year, p.month)
    }

    var body: some View {
        let items = store.unplacedEvents
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("未配置").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Text("\(items.count)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                Button("\(monthLabel)を回収") { confirmRecall = true }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                Button("並び替え") {
                    withAnimation(.snappy) { store.sortUnplaced() }
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .controlSize(.mini)
                Spacer()
                Button {
                    withAnimation(.snappy) { collapsed.toggle() }
                } label: {
                    Image(systemName: collapsed ? "chevron.up" : "chevron.down").font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if !collapsed {
                Divider()
                HStack(spacing: 0) {
                    ScrollView {
                        if items.isEmpty {
                            Text("すべて配置済みです")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 24)
                        } else {
                            FlowLayout(spacing: 6) {
                                ForEach(items) { chip($0) }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    backZone
                }
                .frame(height: 120)
            }
        }
        .background(Color(.secondarySystemBackground))
        .confirmationDialog("\(monthLabel)の配置済み予定をすべて未配置に戻しますか?",
                            isPresented: $confirmRecall, titleVisibility: .visible) {
            Button("未配置に戻す", role: .destructive) {
                withAnimation(.snappy) { store.recallMonth(of: anchor) }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }

    private func chip(_ ev: ShiftEvent) -> some View {
        let color = Color(hex: ev.color)
        let time = Rules.timeLabel(ev)
        return HStack(spacing: 4) {
            Text(ev.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
            if !time.isEmpty {
                Text(time).font(.system(size: 9)).foregroundStyle(color.opacity(0.7))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.16))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture { onSelectEvent(ev) }
        .draggable(ev.id)
    }

    private var backZone: some View {
        VStack(spacing: 2) {
            Image(systemName: "tray.and.arrow.down").font(.title3)
            Text("未配置\nに戻す").font(.system(size: 9)).multilineTextAlignment(.center)
        }
        .foregroundStyle(backTargeted ? Theme.accent : Color.secondary)
        .frame(width: 72)
        .frame(maxHeight: .infinity)
        .background(backTargeted ? Theme.accent.opacity(0.12) : Color(.tertiarySystemFill))
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first else { return false }
            withAnimation(.snappy) { store.unplace(id: id) }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            return true
        } isTargeted: { backTargeted = $0 }
    }
}
```

- [ ] **Step 3: コミットする**

```bash
cd /c/tmp/shift_ro
git add ios
git commit -m "feat(ios): 未配置エリア(チップ・回収・並び替え・戻すゾーン)を追加

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: ドロップ受け・ドラッグ元・エディタ・ルートの結線 + CI

**Files:**
- Modify: `ios/Shift/Views/Calendar/EventBar.swift`
- Modify: `ios/Shift/Views/Calendar/MonthView.swift`
- Modify: `ios/Shift/Views/Calendar/WeekView.swift`
- Modify: `ios/Shift/Views/Editor/EventEditor.swift`
- Modify: `ios/Shift/Views/RootView.swift`

**Interfaces:**
- Consumes: `Store.place(id:on:)`、`UnplacedArea`(Task 2)
- Produces: `MonthView` / `WeekView` の新しい引数 `onDropEvent: (String, String) -> Void`(引数は 予定ID、日付 `yyyy-MM-dd`)。配置済みのバー/ブロックも `draggable(id)` になる。`EventEditor` は日付を空にして未配置として保存できる。

- [ ] **Step 1: EventBar.swift — バーをドラッグ元にする**

`SpanBars` 内の `.onTapGesture { onSelect(s.event) }` の直後の行に `.draggable(s.event.id)` を追加する。

```swift
                        .onTapGesture { onSelect(s.event) }
                        .draggable(s.event.id)
```

- [ ] **Step 2: MonthView.swift — 日付へのドロップを受ける**

(a) プロパティ `let onSelectEvent: (ShiftEvent) -> Void` の直後に追加:

```swift
    let onDropEvent: (String, String) -> Void
```

(b) `weekRow` 内の、`GeometryReader { geo in ... }` の中の `ZStack(alignment: .topLeading) { ... }` の閉じ括弧の直後(`}` の次の行)に、`dropDestination` を追加する。バー(兄弟ビュー)の上に落としても受けられるように、ZStack 全体で受けて x 座標から列を求める。

```swift
            .dropDestination(for: String.self) { ids, location in
                guard let id = ids.first else { return false }
                let col = min(6, max(0, Int(location.x / w)))
                guard let ds = cells[col] else { return false }
                onDropEvent(id, ds)
                return true
            }
```

- [ ] **Step 3: WeekView.swift — 日列へのドロップを受け、ブロックをドラッグ元にする**

(a) プロパティ `let onSelectEvent: (ShiftEvent) -> Void` の直後に追加:

```swift
    let onDropEvent: (String, String) -> Void
```

(b) `grid(_:)` 内の `column(days[i], colW: colW, H: H)` に続く `.frame(width: colW, height: H, alignment: .topLeading)` の直後の行に追加(`.overlay` と `.offset` の前):

```swift
                        .dropDestination(for: String.self) { ids, _ in
                            guard let id = ids.first else { return false }
                            onDropEvent(id, days[i])
                            return true
                        }
```

(c) `column(...)` 内の `.onTapGesture { onSelectEvent(ev) }` の直後の行に追加:

```swift
                        .draggable(ev.id)
```

- [ ] **Step 4: EventEditor.swift — 「日付を指定」トグルを追加する**

(a) `@State private var confirmDelete = false` の直前に追加:

```swift
    @State private var hasDate: Bool
```

(b) `init` 内の `_allDay = State(initialValue: original.allDay)` の直前に追加:

```swift
        _hasDate = State(initialValue: original.startDate != nil)
```

(c) 日付の `Section` を次のとおり置き換える(現在は `DatePicker("開始日"...)`, `DatePicker("終了日"...)`, `Toggle("終日"...)`, `if !allDay { timeRows }` が並んでいる):

```swift
                Section {
                    Toggle("日付を指定", isOn: $hasDate)
                    if hasDate {
                        DatePicker("開始日", selection: $start, displayedComponents: .date)
                        DatePicker("終了日", selection: $end, in: start..., displayedComponents: .date)
                    }
                    Toggle("終日", isOn: $allDay)
                    if !allDay { timeRows }
                }
```

(d) `build()` 内の次の3行を置き換える。

置き換え前:
```swift
        e.startDate = sd
        e.endDate = Rules.resolveEndDate(start: sd, end: Rules.format(end), allDay: allDay, startTime: st, endTime: et)
        e.placed = true
```
置き換え後:
```swift
        if hasDate {
            e.startDate = sd
            e.endDate = Rules.resolveEndDate(start: sd, end: Rules.format(end), allDay: allDay, startTime: st, endTime: et)
            e.placed = true
        } else {
            e.startDate = nil
            e.endDate = nil
            e.placed = false
        }
```

- [ ] **Step 5: RootView.swift — 未配置エリアの配置とドロップの結線**

(a) `MonthView(...)` と `WeekView(...)` の呼び出しに `onDropEvent: drop` を追加する(`onSelectEvent: edit` の後ろ):

```swift
                    MonthView(anchor: anchor, startMonday: startMonday, onSelectDay: addEvent, onSelectEvent: edit, onDropEvent: drop)
                ...
                    WeekView(anchor: anchor, startMonday: startMonday, onSelectDay: addEvent, onSelectEvent: edit, onDropEvent: drop)
```

(b) `if showSummary > 0 { SummaryBar(...) }` の直後(VStack の最後の子)に追加:

```swift
            UnplacedArea(anchor: anchor, onSelectEvent: edit)
```

(c) `private func edit(_ event: ShiftEvent) { ... }` の直後に追加:

```swift
    private func drop(id: String, on date: String) {
        withAnimation(.snappy) { store.place(id: id, on: date) }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
```

- [ ] **Step 6: コミットして push する**

```bash
cd /c/tmp/shift_ro
git add ios
git commit -m "feat(ios): ドラッグ&ドロップで日付へ配置・未配置へ戻す機能を結線

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
git push
```

- [ ] **Step 7: CI を確認する**

ユーザーが Codemagic の `Shift iOS test`(ブランチ `feat/ios-swiftui`)を開始する。GitHub の check-runs で結果を確認する。
Expected: 緑。`StoreUnplacedTests` の 10 件を含む全テストが PASS する。
失敗時は最初の `error:` を直す。想定される失敗は、`dropDestination` の closure 型、`FlowLayout` の `cache: inout ()` の書き方、`@ViewBuilder` 内の型推論の3つ。

---

## Self-Review

**Spec coverage**

| 設計書の項目 | タスク |
|---|---|
| 配置(日数保持、`resolveEndDate`) | Task 1 |
| 未配置に戻す(末尾へ) | Task 1, 2 |
| 並び替え(Web版と同一の順序) | Task 1, 2 |
| 回収(確認ダイアログ付き) | Task 1, 2 |
| 未配置エリア(件数、折りたたみ、戻すゾーン) | Task 2 |
| 月/週へのドラッグ配置、配置済みの移動 | Task 3 |
| 編集シートで日付を空にして未配置にする | Task 3 |
| 触覚フィードバック | Task 2, 3 |

**型の整合性**: `Store.place(id:on:)` は Task 1 で定義し、Task 3 の `drop(id:on:)` が呼ぶ。`UnplacedArea(anchor:onSelectEvent:)` は Task 2 で定義し、Task 3 が呼ぶ。`onDropEvent: (String, String) -> Void` は Month/Week で同じ形で、RootView の `drop(id:on:)` が `(String, String) -> Void` として渡る(`addEvent(on:)` と同じ関数参照の形)。

**リスク**: Swift の環境がローカルにない。`dropDestination` の closure の型と `FlowLayout` はコンパイラ頼みで、CI で初めて確認できる。
