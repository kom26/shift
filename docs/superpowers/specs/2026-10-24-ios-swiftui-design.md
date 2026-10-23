# シフト管理 iOSネイティブ化 設計書

## 目的
`index.html`(React/localStorage)のシフト管理ツールを、SwiftUI製のiOS専用ネイティブアプリに移植する。
軽量・シンプルで、今後の機能追加がしやすい構造にする。

## 前提・決定事項
- 対象: iOSのみ(iOS 17+)、SwiftUI、外部ライブラリなし
- ビルド/配布: Codemagic(Echoと同じ運用)。Windows開発のためローカルビルドはしない
- 配置: `kom26/shift` の `ios/` 配下。Web版は残す。`codemagic.yaml` は `ios/` に置く
- Xcodeプロジェクトは xcodegen(`project.yml`)で生成し、`.xcodeproj` はコミットしない

## データ
- `ShiftEvent: Codable, Identifiable`
  - id, title, memo, color(hex), startDate("yyyy-MM-dd"), endDate?, allDay, startTime?("HH:mm"), endTime?("HH:mm"), workHours?
  - 日付・時刻はWeb版と同じ文字列で保持する(24:00の扱い・日またぎ判定を同一挙動にするため)
  - 項目追加はOptionalで行い、スキーマ移行を不要にする
- 保存: `[ShiftEvent]` を1つのJSONファイルに保存(App Groupコンテナ。将来のウィジェット共有用)
- 設定(表示モード、週の起点、集計表示)・カスタム色・色フィルタ: UserDefaults
- Web版移行: 設定画面で `shift-sched-events` 形式のJSONを読み込む。不正なJSONはエラー表示のみで既存データは変更しない

## 構成
```
ios/
  project.yml  codemagic.yaml
  Shift/
    App.swift
    Core/    ShiftEvent.swift  Store.swift  Rules.swift  Holidays.swift
    Views/
      Calendar/  MonthView.swift  WeekView.swift  SpanLayout.swift
      Editor/    EventEditor.swift
      Sidebar/   FilterSheet.swift  SettingsView.swift
  ShiftTests/    RulesTests.swift  SpanLayoutTests.swift  StoreTests.swift
```
- `Rules`: resolveEndDate、calcWorkHours(休憩: 6h超で45分、8h超で60分)、曜日種別、週の起点。UI非依存の純粋関数
- `Holidays`: 内蔵テーブル + holidays-jp APIで更新しキャッシュ。API失敗時は内蔵テーブルで動作
- `SpanLayout`: 複数日バーの配置計算(Web版 computeWeekSpans 相当)。月/週で共用
- `Store`: `@Observable`。追加/更新/削除/複製、色フィルタ、JSON入出力

## 機能ロードマップ
- v1(コア): 月/週(24hグリッド)表示、予定の追加・編集・複製・削除、色とフィルタ、祝日、勤務時間計算、JSON取り込み。移動は編集シートで日時変更
- v2: `draggable`/`dropDestination` によるドラッグ移動、リサイズ、未配置エリア
- v3: 一括インポート、ウィジェット
- 各機能は1ファイル追加を基本とし、既存コードの変更を最小にする

## UI
- 配色はWeb版を踏襲(accent indigo、ライト/ダーク対応)
- 月↔週の切替に matchedGeometryEffect、左右スワイプで期間移動、保存・移動時に触覚フィードバック

## テスト・検証
- Rules / SpanLayout / Store を Swift Testing で単体テスト(Web版の既存挙動を期待値にする)
- CIで `xcodebuild test` を実行し、通ったものだけを実機確認へ進める
