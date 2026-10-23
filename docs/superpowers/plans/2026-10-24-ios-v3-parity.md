# シフト管理 iOS v3(Web版パリティ) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Web版との差分表(`docs/superpowers/specs/2026-10-24-web-feature-inventory.md`)の ❌/⚠️ と、ユーザー報告の不具合を全て埋める。

**Architecture:** 解釈が要る処理(集計、CSV、一括取り込み、月グリッド)は `Core/` の純粋関数にしてテストする。UIは共通部品(ドロップ受け、集計ストリップ、共有シート)を先に作り、月・週・ヘッダー・ドロワーで使い回す。

**Tech Stack:** Swift 5 モード、SwiftUI(iOS 17)、Swift Testing。外部ライブラリなし。

## Global Constraints

設計書 `docs/superpowers/specs/2026-10-24-ios-v3-parity-design.md` が正。要点:

- iOS 17+、SwiftUI のみ、外部ライブラリなし。データモデル `ShiftEvent` は変更しない
- Web版 `/c/tmp/shift_ro/index.html` の挙動が正。判断に迷ったら差分表(`web-inventory`)の「Web behavior」列と該当の行番号を読む
- 色フィルタは現状どおり(選んだ色の予定だけをカレンダーにも出す。`Store.visibleEvents`)
- 日付は `yyyy-MM-dd` 文字列。全てのテキストは日本語(`Rules`/ビューの文言は既存に合わせる)
- 入れない機能: バー端リサイズ、未配置の手動並べ替え、サンプルデータ、キーボードショートカット、PCサイドバー開閉

## 作業の進め方(全タスク共通)

- Swift ツールチェーンはローカルにない。コンパイルとテストは Codemagic の `Shift iOS test` が行い、`feat/ios-*` への push で**自動で走る**(約3〜5分)。結果は GitHub の check-runs で確認する
- 各タスクは、実装 → コミット → (コントローラが)push → CI の緑を確認、の順。赤なら失敗ログの要約(ログ末尾の `=== FAILURE DETAILS ===`)を直してから次へ進む
- **テストの `ev(...)` ヘルパーの引数順**は `ev(id, start, end, color:, allDay:, placed:, st:, et:, wh:)`(`allDay` は `placed` より前)。`ios/ShiftTests/Fixtures.swift` を必ず確認する
- 新しい `Store`/`Rules` の関数は、先にテストを書く。期待値はこの計画に書いてある値を使う

---

### Task 1: Core ロジックとテスト

**Files:**
- Modify: `ios/Shift/Core/Rules.swift`、`ios/Shift/Core/Store.swift`
- Create: `ios/Shift/Core/CSVExport.swift`、`ios/Shift/Core/BulkImport.swift`
- Create (tests): `ios/ShiftTests/MonthGridTests.swift`、`ios/ShiftTests/SummaryTests.swift`、`ios/ShiftTests/CSVExportTests.swift`、`ios/ShiftTests/BulkImportTests.swift`、`ios/ShiftTests/StoreExtrasTests.swift`

**Interfaces (Produces):**
- `Rules.monthGrid(year: Int, month: Int, startMonday: Bool) -> [[String]]` — 隣接月を含む全日付の月グリッド(各週7日、`nil`なし)。行数は既存 `monthWeeks` と同じ
- `Rules.isSameMonth(_ ds: String, as anchor: String) -> Bool`
- `ColorTotal` に `var title: String` を追加(`Store.totals(from:to:)` は、その色で最初に数えた予定のタイトルを入れる)
- `struct PanelRow: Identifiable { color: String; title: String; placed: Double; unplaced: Double; id: String }` と `Store.monthPanel(of anchor: String) -> [PanelRow]`
- `Store.duplicate(id: String)` — 同じ内容で新ID、配置済みなら最後の配置済みの直後、未配置なら末尾に入れる。存在しないIDは何もしない
- `Store.append(_ new: [ShiftEvent])` — 配置済み → 既存の未配置 → 新規、の順に並べる
- `CSVExport.make(events: [ShiftEvent], month anchor: String) -> String`、`CSVExport.fileName(for anchor: String) -> String`
- `BulkImport.parse(_ text: String) -> [(title: String, memo: String)]`、`BulkImport.makeEvents(_ rows: [(title: String, memo: String)], color: String) -> [ShiftEvent]`

**仕様と期待値(テストにそのまま使う):**

- **monthGrid(2026, 10, false)**: 5週。`[0][0] == "2026-09-27"`、`[0][4] == "2026-10-01"`、`[4][6] == "2026-10-31"`。**monthGrid(2026, 10, true)**: 5週。`[0][0] == "2026-09-28"`、`[4][6] == "2026-11-01"`。**monthGrid(2026, 2, false)**(2026年2月は日曜始まりで4週ちょうど): 4週、`[0][0] == "2026-02-01"`、`[3][6] == "2026-02-28"`。全セルが `yyyy-MM-dd` 形式
- **isSameMonth**: `("2026-10-31", as: "2026-10-01")` は true、`("2026-11-01", as: "2026-10-15")` は false
- **totals の title**: 同じ色の予定が2件あるとき、最初の予定のタイトルが入る(`ev(...)` は `title == id` になる)
- **monthPanel(of: "2026-10-15")** — Web版の月集計(`index.html` L636-659 付近、L223-229): **色フィルタを無視**して全予定を走査する。実労働時間(`effectiveHours`)が nil か 0 の予定は数えない。配置済みで開始日が10月の予定は `placed` に、**月に関係なく全ての未配置**は `unplaced` に加算する。行のタイトルは、その色で最初に数えた予定のタイトル。`placed == 0 && unplaced == 0` の色は出さない。行の順は、色が最初に現れた順。期待値の例: 10/5 の 09:00-18:00(8h)青、10/6 の 10:00-14:00(4h)青、11/2 の 09:00-18:00 青、未配置の 15:00-23:00 青(7.25h)、未配置の 07:00-15:00 赤(7.25h) → 青は placed 12 / unplaced 7.25、赤は placed 0 / unplaced 7.25
- **duplicate**: 配置済み `a`、未配置 `u`、配置済み `b` の並びで `a` を複製 → `[a, b, a複製, u]`(複製は新IDで `a` と同じ日付・内容)。`u` を複製 → 末尾に追加。存在しないIDは並び不変
- **append**: `[p, u1]` に新規2件 `[n1, n2]` を追加 → `[p, u1, n1, n2]`(`p` は配置済み)
- **CSVExport.make(events:month:)** — Web版 `handleExportCSV`(`index.html` L1158-1187): 先頭に BOM(`"\u{FEFF}"`)。1行目は `"状態","日付","開始","終了","実労働時間","メモ"`。次に、開始日が対象月に入る配置済み予定を開始日の昇順(同日は元の順)で `"配置済","2026/10/05","09:00","18:00","8h","メモ"` の形(日付は `-` を `/` に置換。時刻がない場合は空文字。実労働時間は `workHours` が非nilのとき `Rules.formatHours`、nil は空文字)。そのあと、**全ての**未配置予定を `"未配置","", 開始, 終了, 時間, メモ` の形で並べる。全セルをダブルクォートで囲み、中の `"` は `""` にする。行は `\r\n` で連結(末尾の改行なし)。タイトル列はない。**fileName(for: "2026-10-15") == "shifts_202610.csv"**
- **BulkImport.parse**: `text` を前後の空白・改行で trim → `\n` で分割 → 各行を `\t` で分割。タイトル = 1列目を trim、メモ = 2列目を trim(なければ空文字、3列目以降は無視)。タイトルが空の行は捨てる。例: `"早番\t7:00から15:00\n夜勤\n\n遅番\t\n"` → `[("早番","7:00から15:00"), ("夜勤",""), ("遅番","")]`。Windows 改行 `\r\n` でも結果は同じ
- **BulkImport.makeEvents**: 各行から `ShiftEvent` を作る。新ID(UUID)、タイトル・メモ・色、`startDate == nil`、`endDate == nil`、`placed == false`、`allDay == true`、時刻・実労働時間は nil

- [ ] **Step 1: テストを書く** — 上の期待値を、各テストファイルに Swift Testing(`import Testing`、`@testable import Shift`、`@Test`、`#expect`)で書く。`Store` を作るテストは既存の `StoreUnplacedTests.swift` の `make()` と同じ方法(一時ファイル + UUID の UserDefaults suite)を使う
- [ ] **Step 2: 実装する** — `Rules`、`Store`、`CSVExport`、`BulkImport` を追加する。`Store.totals` の `ColorTotal` 生成箇所に `title` を追加する。既存テストを壊さない(`monthWeeks` はそのまま残す)
- [ ] **Step 3: コミットする**(`git commit -m "feat(ios): 月グリッド・集計・CSV・一括取り込みのロジックを追加"`、末尾に `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`)

---

### Task 2: 共通UI部品・ローカライズ・セーフエリア

**Files:**
- Modify: `ios/project.yml`、`ios/Shift/App.swift`、`ios/Shift/Views/Theme.swift`、`ios/Shift/Views/Sidebar/UnplacedArea.swift`、`ios/Shift/Views/Calendar/EventBar.swift`、`ios/Shift/Core/ShiftEvent.swift`
- Create: `ios/Shift/Views/Calendar/EventDropDelegate.swift`、`ios/Shift/Views/Sidebar/SummaryStrip.swift`、`ios/Shift/Views/ShareSheet.swift`、`ios/Shift/Views/Calendar/EventMenu.swift`

**Interfaces (Produces):**
- `ShiftEvent.newUnplaced() -> ShiftEvent` — 日付なし・`placed == false`・`allDay == true`・色は既定の `#6366f1`・タイトル空
- `Theme.accent` を、ライトは `#4f46e5`、ダークは `#818cf8` に切り替わる動的な色にする(`UIColor { trait in ... }` を使う)。`Theme.accentSoft` を追加(ライト `#eef2ff`、ダーク `#1e1d3a`)
- `EventDropDelegate: DropDelegate` — `init(resolve: @escaping (CGPoint) -> String?, target: Binding<String?>, onDrop: @escaping (String, String) -> Void)`。`dropUpdated` で `resolve(info.location)` の日付を `target` に入れ、`DropProposal(operation: .move)` を返す(「+」バッジを出さない)。`dropEntered`/`dropExited` でも `target` を更新(Exited で nil)。`validateDrop` は文字列の項目があれば true。`performDrop` は `info.itemProviders(for: [.plainText]).first` から `NSString` を読み込み、メインスレッドで `onDrop(id, date)` を呼び、`target` を nil にして true を返す
- `SummaryStrip(label: String?, totals: [ColorTotal], emptyText: String)` — 横スクロールのチップ列。各チップは色の点・タイトル・`XhYm`(`Rules.formatHours`)。`totals.count > 1` のときは末尾に `合計 XhYm` を出す。`totals` が空なら `emptyText` を表示。`label` があれば先頭に小さく出す。高さは約22pt
- `ShareSheet(items: [Any])` — `UIActivityViewController` を包む `UIViewControllerRepresentable`
- `EventMenu` — `ViewModifier` と `View.eventMenu(for event: ShiftEvent, store: Store, onEdit: @escaping (ShiftEvent) -> Void)`。`.contextMenu` に「編集」「複製」(`store.duplicate`)、「未配置に戻す」(配置済みのときだけ。`store.unplace`)、「削除」(`role: .destructive`、`store.delete`)を出す

**変更内容:**
- `project.yml`: Shift ターゲットの `settings.base` に `DEVELOPMENT_LANGUAGE: ja` を追加。`options` に `developmentLanguage: ja` を追加
- `App.swift`: `RootView()` に `.environment(\.locale, Locale(identifier: "ja_JP"))` を追加
- `UnplacedArea`: 背景色(`secondarySystemBackground`)をホームインジケータの下まで伸ばす(`.background(Color(.secondarySystemBackground).ignoresSafeArea(edges: .bottom))`)。中身はセーフエリア内のまま。空状態の文言は `すべて配置済みです 🎉`。回収の確認文は `YYYY年M月の配置済み予定をすべて未配置に戻しますか?`(ボタン名の `YYYY/MM を回収` は今のまま)。チップ領域の背景にも「未配置に戻す」のドロップを受ける(`dropDestination(for: String.self)` ではなく `EventDropDelegate` を使い、`resolve` は常に `"unplace"` を返し、`onDrop` の第2引数は無視して `store.unplace(id:)` を呼ぶ。戻すゾーンも同じ方式にそろえて「+」を出さない)
- `EventBar.swift`(`EventBar`/`SpanBars`): 見た目を Web版に合わせる。背景は色の16%(`color.opacity(0.16)`)、文字は色そのもの(太字、10pt、1行、末尾省略)。先頭セグメント(`isStart`)の左に3ptの縦線(色)。継続セグメント(`!isStart`)は文字を `…` にして縦線なし。文言は `allDay || startTime == nil` ならタイトル、それ以外は `Rules.timeLabel`(`HH:MM〜HH:MM`)。角丸は `isStart`/`isEnd` に応じて既存どおり。バーの高さは呼び出し側が渡す `barH`(月ビューは20)
- `SpanBars` の**ドラッグ元の付け方を直す**: 各バーは `EventBar → .frame(width:height:) → .onTapGesture → .eventMenu(...) → .draggable(id)` の順に付けてから、**最後に** `.offset(x:y:)` を付ける(`offset` を `draggable` より後ろにする)。`SpanBars` に引数 `onEdit: (ShiftEvent) -> Void` と `store` の受け取り(`@Environment(Store.self)`)を追加する。呼び出し側(`MonthView`/`WeekView`)の更新は Task 3・4 で行うので、**このタスクでは `SpanBars` の既存引数 `onSelect` をそのまま残し、`onEdit` には `onSelect` と同じ関数を使う**(`SpanBars` 内で `onSelect` を `eventMenu` の `onEdit` にも渡す)
- `ShiftEvent.swift`: `newUnplaced()` を追加

- [ ] **Step 1〜**: 上の内容を実装する。`EventDropDelegate` の読み込みは `NSItemProvider.loadObject(ofClass: NSString.self) { obj, _ in ... }` を使い、結果の `String` を `DispatchQueue.main.async` で `onDrop` に渡す
- [ ] **最後**: コミットする(`git commit -m "feat(ios): 共通UI部品・日本語ロケール・セーフエリア対応を追加"`)

---

### Task 3: 月ビューの作り直し

**Files:**
- Modify: `ios/Shift/Views/Calendar/MonthView.swift`(ほぼ書き直し)、`ios/Shift/Views/RootView.swift`(`MonthView` の呼び出し)

**Interfaces:**
- Consumes: Task 1(`Rules.monthGrid`、`Rules.isSameMonth`、`Store.totals`)、Task 2(`EventDropDelegate`、`SummaryStrip`、`Theme.accentSoft`、`SpanBars`)
- Produces: `MonthView(anchor:startMonday:summaryMode:onSelectDay:onSelectEvent:onDropEvent:)` — `summaryMode: Int`(0 なし/1 週計/2 月計)を追加。`onSelectEvent` は `(ShiftEvent) -> Void`(従来どおり)。`RootView` の呼び出しも更新する

**仕様(Web版 `index.html` の MonthView L401-595 を読んで合わせる):**
- グリッドは `Rules.monthGrid(...)` を使い、隣接月の日も表示する。隣接月のセル: 日付の数字を薄く(不透明度0.45)、背景は `Color(.tertiarySystemFill)`、祝日名なし、今日扱いにしない。**予定は隣接月の日にも描き、セルのタップ(その日に追加)とドラッグ配置も当月と同じようにできる**
- 曜日見出し(日赤・土青)は今のまま。祝日の数字は赤(`Rules.dayType` と `Holidays`)、祝日名はセルに**出さない**
- 今日のセル: 背景を `Theme.accentSoft`、数字は `Theme.accent`
- 行の高さ: `numH = 22`、`barH = 20`、バー間隔 2、下余白 6。`rowHeight = max(minRow, numH + バー段数 * (barH + 2) + 6 + (summaryMode == 1 ? 24 : 0))`。`minRow` は「利用可能な高さ ÷ 週数」(`GeometryReader` で取る)。全体は縦 `ScrollView` に入れ、予定が増えたら行が伸びてスクロールできる。バー段数は `SpanLayout.rows(...)` の `rows.count`
- バー: `SpanBars` を使い、`leading: 0`。`colW = 幅/7`
- `summaryMode == 1`(週計): 各週の行の下端に `SummaryStrip(label: nil, totals: ..., emptyText: "-")` を出す。その週の7日(隣接月を含む)に**開始日がある**予定を集計する(`store.totals(from: 週の最初の日, to: 週の最後の日)`)
- `summaryMode == 2`(月計): 月ビューの**下端に固定**で `SummaryStrip(label: "月計", totals: store.totals(from: 月初, to: 月末), emptyText: "データなし")` を1本出す(スクロールの外、`UnplacedArea` の上)。`Rules.monthBounds(of: anchor)` を使う
- ドロップ: 各週の行に `onDrop(of: [.plainText], delegate: EventDropDelegate(resolve: { 位置の x から列を求め、その週の日付を返す }, target: $dropTarget, onDrop: onDropEvent))` を付ける。`dropTarget`(`@State String?`)と一致するセルを、背景 `Theme.accentSoft` と、2ptの点線の枠(`Theme.accent`)でハイライト。`.dropDestination` は使わない(「+」が出るため)
- ドラッグ元は Task 2 の `SpanBars` の順序(`offset` が最後)に従う。**`MonthView` 側で `.offset` の後に `.draggable`/`.onTapGesture` を付けない**
- 日セルのタップで `onSelectDay(日付)`(隣接月の日も)。バーのタップで `onSelectEvent`

- [ ] 実装し、コミットする(`git commit -m "feat(ios): 月ビューを作り直し(隣接月・伸びる行・週計・ハイライト)"`)

---

### Task 4: 週ビューの作り直し

**Files:**
- Modify: `ios/Shift/Views/Calendar/WeekView.swift`、`ios/Shift/Views/RootView.swift`(`WeekView` の呼び出し)

**Interfaces:**
- Consumes: Task 1、Task 2
- Produces: `WeekView(anchor:startMonday:summaryMode:onSelectDay:onSelectEvent:onDropEvent:)`

**仕様(Web版 WeekView L205-399 を読んで合わせる):**
- 時刻ラベル: 毎正時(1〜23)に数字を表示(0時は空)。ラベル列の幅は 22pt。線は、正時が不透明度0.5、30分が0.2
- 週ヘッダー: 曜日、日付の数字、**祝日名(9pt、赤、1行・末尾省略)**を日付の下に出す。今日はヘッダー背景を `Theme.accentSoft`、数字を `Theme.accent`(白丸はやめる)
- 終日行: `SpanLayout` のバーを `barH = 20` で出す(`SpanBars`)。**行の空白タップでその日に追加**(列ごとに `onSelectDay`)。行全体が**ドロップ先**(`EventDropDelegate`、`resolve` は x から列→日付)。終日がない週は行の高さ0
- 時間ブロック: 塗りは `color.opacity(0.8)`、1ptの枠(色)、文字は白・太字・タイトル10pt(影あり)、時間ラベル9pt(ブロック高さが 30pt 超のとき)。ブロックの `.draggable`/`.eventMenu`/`.onTapGesture` は **`.offset` より前**に付ける
- 各日の列は `onDrop(of: [.plainText], delegate: EventDropDelegate(resolve: { _ in 日付 }, ...))` で受け、`dropTarget` の列は背景 `Theme.accentSoft` でハイライト
- 現在時刻線: 今日の列に、赤(`Color.red`)の2pt線と直径8ptの点。`TimelineView(.everyMinute)` で分ごとに更新。位置は `H * 現在の分 / 1440`
- `summaryMode == 1`(週計): 画面下端に固定で `SummaryStrip(label: "週計", totals: store.totals(from: 週初, to: 週末), emptyText: "データなし")`。`summaryMode == 2` では何も出さない
- 週ヘッダー全体のタップは何もしない(Web版と同じ)。列の空白タップで追加(今のまま)

- [ ] 実装し、コミットする(`git commit -m "feat(ios): 週ビューを作り直し(時刻線・祝日名・ハイライト・週計)"`)

---

### Task 5: ヘッダー、☰ドロワー、CSV、ルート結線

**Files:**
- Create: `ios/Shift/Views/Sidebar/DrawerSheet.swift`
- Modify: `ios/Shift/Views/RootView.swift`(ほぼ書き直し)、`ios/Shift/Views/Sidebar/SettingsView.swift`(そのまま使う。ドロワーから開く)
- Delete: `ios/Shift/Views/Sidebar/FilterSheet.swift`、`ios/Shift/Views/Sidebar/SummaryBar.swift`(不要になる。参照も消す)

**Interfaces:**
- Consumes: Task 1〜4
- Produces: `DrawerSheet(anchor: String, onEdit: (ShiftEvent) -> Void, onAddUnplaced: () -> Void, onBulkImport: () -> Void, onSettings: () -> Void)`

**ヘッダー(Web版のモバイル構成 `index.html` L1232-1272):**
- 1行目: ☰ボタン(ドロワーを開く) | `‹` タイトル `›` | `＋ 追加` ボタン(アクセント色の塗り)。`＋ 追加` は `ShiftEvent.newUnplaced()` で**未配置**の新規予定として編集画面を開く(日付を指定していないので、保存すると未配置エリアに入る)
- 2行目: 週|月(セグメント) | `今日` | `日始`/`月始`(押すと `startMonday` を切り替え。表示は現在の状態: `startMonday` が false なら `日始`) | 集計ボタン(`集計`→`週計`→`月計`、オンのときはアクセント色の枠と淡い背景) | `CSV`
- タイトル・スワイプ・触覚は今のまま。`@AppStorage("showSummary")` を `summaryMode` として `MonthView`/`WeekView` に渡す

**ドロワー(シート。`NavigationStack`、タイトル「予定リスト」、右上に「完了」)— Web版 Sidebar L598-695:**
- 「月集計 YYYY/MM」セクション(`DisclosureGroup`、**既定は閉じる**): `store.monthPanel(of: anchor)` の各 `PanelRow` を、色のチェック(`store.checkedColors.contains`、タップで `store.toggleColor`)、色の点、タイトル、`配置済 Xh` と `未配置 Xh`(`Rules.formatHours`)で出す。行が無ければ `データなし`。「すべて表示」ボタン(`store.clearColors()`、フィルタ中のみ有効)
- 「予定」セクション: **全予定**を、配置済みは開始日の昇順(同日は元の順)、そのあとに未配置(元の順)。各行: 色の縦線、タイトル、`MM/DD`(複数日なら `MM/DD → MM/DD`)、`Rules.timeLabel`、`実労働(workHours があれば XhYm)`。未配置は `未配置`。タップで `onEdit`(ドロワーを閉じてから編集画面を開く)
- 下部のボタン: `＋ 予定を追加`(`onAddUnplaced`)、`一括取り込み`(`onBulkImport`)、`設定`(`onSettings`)

**CSV:**
- `CSV` ボタンで `CSVExport.make(events: store.events, month: anchor)` を UTF-8 で一時ファイル(`FileManager.default.temporaryDirectory`、名前は `CSVExport.fileName(for: anchor)`)に書き、`ShareSheet(items: [fileURL])` をシートで開く

**RootView の構成:** ヘッダー → カレンダー(月は `MonthView`、週は `WeekView`) → `UnplacedArea`。シートは、編集(`EventEditor`)、ドロワー、設定(`SettingsView`)、一括取り込み(Task 6 で作る `BulkImportSheet`。**このタスクでは `onBulkImport` の遷移だけ作り、`BulkImportSheet` が無い間は `Text("準備中")` を表示するプレースホルダーのシートにしておく**)。ドロワーから別シートへ移るときは、ドロワーを閉じてから次のシートを開く(`DispatchQueue.main.asyncAfter` で少し遅らせる)

- [ ] 実装し、コミットする(`git commit -m "feat(ios): ヘッダーを再構成し、☰ドロワー・CSV出力を追加"`)

---

### Task 6: 一括取り込み・編集画面・仕上げ

**Files:**
- Create: `ios/Shift/Views/Editor/BulkImportSheet.swift`
- Modify: `ios/Shift/Views/RootView.swift`(プレースホルダーを置き換え)、`ios/Shift/Views/Editor/EventEditor.swift`、`ios/Shift/Views/Sidebar/UnplacedArea.swift`

**Interfaces:**
- Consumes: `BulkImport.parse/makeEvents`、`Store.append`、`Store.defaultColors`、`Color(hex:)`
- Produces: `BulkImportSheet()`(`@Environment(Store.self)`、`dismiss`)

**一括取り込みシート(Web版 BulkImportModal L922-995):**
- タイトル「一括取り込み」。説明文: `エクセル・スプシから予定名・メモをコピーして貼り付け（タブ区切り2列、1行1予定）`
- `TextEditor`(貼り付け欄、最小高さ 140pt)と、`クリップボードから貼り付け` ボタン(`UIPasteboard.general.string` を欄に入れる)。プレースホルダー代わりに、欄が空のときは薄い例文 `早番シフト⇥7:00から15:00まで` / `夜勤バイト⇥22:00から翌朝` / `遅番シフト⇥`(⇥はタブ)を重ねて表示
- `BulkImport.parse` の結果が1件以上なら、`プレビュー（N件）` として先頭10件(色の縦線、タイトル、メモ)と、11件以上なら `他 M 件...` を出す
- 色は8色のパレット(`Store.defaultColors`)から1つ選ぶ(既定は先頭)
- ボタン `N件取り込む`(0件のとき無効)。押すと `store.append(BulkImport.makeEvents(rows, color:))` を呼んで閉じる。キャンセルボタンも付ける

**編集画面(`EventEditor`) — Web版 E9:**
- 休憩の入力欄の隣に、`リセット` ボタンを出す(`breakText` が空でなく、かつ既定の休憩分(`defaultBreak`)の文字列と違うときだけ)。押すと `breakText = ""`

**未配置エリア・その他:**
- 長押しメニュー(Task 2 の `eventMenu`)を `UnplacedArea` のチップにも付ける(`onEdit` は `onSelectEvent`)。ドラッグ元(`.draggable`)の前に付ける(順序は `.onTapGesture → .eventMenu → .draggable`)
- `RootView` で `UnplacedArea`・`MonthView`・`WeekView` が使う `onSelectEvent` は、編集画面を開く `edit` のまま

- [ ] 実装し、コミットする(`git commit -m "feat(ios): 一括取り込みと休憩リセットを追加"`)
- [ ] **(Task 7 の後)最終確認**: 全タスクの push 後に CI が緑であることを確認し、`git tag testflight-v3-1` を push して TestFlight に配信する。ユーザーに、確認してほしい項目(ドラッグ位置、隣接月、各週の週計、日本語の日付、セーフエリア、一括取り込み、CSV、長押しメニューと並行したドラッグの動き)を伝える

---

### Task 7: 職場の登録(色の事前登録)と予定作成での選択

**Files:**
- Create: `ios/Shift/Core/Workplace.swift`、`ios/ShiftTests/WorkplaceTests.swift`、`ios/Shift/Views/Sidebar/WorkplaceEditor.swift`
- Modify: `ios/Shift/Core/Store.swift`、`ios/Shift/Views/Sidebar/SettingsView.swift`、`ios/Shift/Views/Editor/EventEditor.swift`

**方針(ユーザー要望):** 設定で「職場」を名前と色で登録しておく。予定を作るとき、タイトルは自由に入力するか、登録済みの職場の一覧から選べる。`ShiftEvent` のデータモデルは変えない。職場は「タイトルと色の入力を省くプリセット」で、予定との紐づけは持たない(タイトルと色をコピーする)。

**Interfaces (Produces):**
- `struct Workplace: Codable, Identifiable, Equatable { var id: String; var name: String; var color: String }`
- `Store.workplaces: [Workplace]`(`private(set)`、UserDefaults のキー `shift-workplaces` に JSON で保存し、起動時に読む)
- `Store.addWorkplace(name: String, color: String)` — 名前の前後の空白を除く。空なら何もしない
- `Store.updateWorkplace(id: String, name: String, color: String, applyToEvents: Bool)` — 名前を trim。空なら何もしない。`applyToEvents == true` のときだけ、**変更前の名前と同じタイトル**を持つ全予定の `title` を新しい名前に、`color` を新しい色に更新して保存する
- `Store.deleteWorkplace(id: String)` — 予定は変更しない
- `Store.moveWorkplaces(from: IndexSet, to: Int)` — 並べ替え
- `Store.eventCount(matchingTitle name: String) -> Int` — タイトルが `name` と完全一致する予定の数(反映の確認ダイアログに使う)

**テスト(期待値):**
- add: `addWorkplace(name: " ドンキ ", color: "#f59e0b")` → `workplaces.count == 1`、`name == "ドンキ"`。空白だけの名前は追加されない
- update(applyToEvents: false): 職場「ドンキ」を「ドンキ新宿」・色変更しても、タイトル「ドンキ」の予定は変わらない
- update(applyToEvents: true): タイトル「ドンキ」の予定が2件(色は別々)と、タイトル「まねき」の予定が1件あるとき、「ドンキ」を「ドンキ新宿」・`#10b981` に更新 → 2件のタイトルが「ドンキ新宿」・色 `#10b981` になり、「まねき」は不変
- eventCount(matchingTitle: "ドンキ") は一致する件数を返す(部分一致はしない)
- delete: 職場が消え、予定は不変
- move: `[A, B, C]` に `moveWorkplaces(from: [0], to: 3)` → `[B, C, A]`
- 永続化: 追加後、同じ `UserDefaults` suite で新しい `Store` を作ると同じ職場が読める

**設定画面(`SettingsView`)に「職場」セクションを追加:**
- 職場の行: 色の点、名前。タップで編集シート(`WorkplaceEditor`)。スワイプで削除。`EditButton` で並べ替え(`onMove` → `moveWorkplaces`)。行がなければ `職場が登録されていません` を薄く表示
- 「＋ 職場を追加」ボタン → `WorkplaceEditor`(新規)
- `WorkplaceEditor`: 名前の `TextField`、色(`Store.defaultColors` の8色のスウォッチと、`ColorPicker`)、「保存」「キャンセル」。名前が空なら保存できない。**既存の職場を編集して名前か色が変わった場合、保存時に `eventCount(matchingTitle: 変更前の名前)` が1以上なら確認ダイアログ**「タイトルが『◯◯』の予定 N 件にも変更を反映しますか?」(ボタン: 「反映する」=`applyToEvents: true`、「この職場だけ変更」=`false`、キャンセル)

**予定の編集画面(`EventEditor`)に職場の選択を追加:**
- タイトル欄の下に、登録済み職場を横スクロールのチップで並べる(色の点+名前)。職場が0件のときはこの行を出さない
- チップをタップすると、`title` を職場名、`color` を職場の色に設定する(タイトル欄は引き続き自由に編集できる)。現在の `title` と一致するチップは選択中の見た目(枠線)にする
- 自由入力のタイトルも今までどおり使える。職場の登録・選択は任意

- [ ] **Step 1: テストを書く** — 上の期待値を `WorkplaceTests.swift` に Swift Testing で書く(`Store` の作り方は `StoreUnplacedTests.swift` の `make()` と同じ。永続化テストは同じ `UserDefaults` suite を再利用する)。`ev(...)` の引数順は `allDay` が `placed` より前
- [ ] **Step 2: 実装する** — `Workplace`、`Store` の追加、`WorkplaceEditor`、`SettingsView`、`EventEditor` の順
- [ ] **Step 3: コミットする**(`git commit -m "feat(ios): 職場の登録と予定作成での選択を追加"`)

---

## Self-Review

**ユーザー報告の対応**: ドラッグ位置(Task 2 の `SpanBars`・Task 4 のブロック)、「+」(Task 2 の `EventDropDelegate`)、日本語の日付(Task 2 の `DEVELOPMENT_LANGUAGE` とロケール)、セーフエリア(Task 2 の `UnplacedArea`)、週計(Task 3)、隣接月(Task 1 の `monthGrid` と Task 3)。

**差分表の ❌/⚠️ の対応**: H5〜H10、SB1、SB3〜SB6、M1〜M7、M10〜M11、M14〜M16、W1〜W3、W5、W7、W9〜W10、U3、U5〜U6、U9、E5、E9、E16、P4、X4 は Task 1〜6 に入っている。入れないと決めたもの(M12、M13 の Ctrl 版、U7、U8、E15、SB2、P2)は設計書に記載済み。M13 は長押しメニューの「複製」で代替。E12(削除の確認)は iOS の確認ありのまま。

**リスク**: 長押しメニュー(`contextMenu`)とドラッグ(`draggable`)を同じビューに付けた動きは、実機で確認が必要(競合した場合は、メニューをやめてドラッグを優先する)。`DropDelegate` の `.move` の見た目も実機で確認する。
