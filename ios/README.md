# シフト管理 iOS

`index.html`(Web版)の SwiftUI 移植。設計は `docs/superpowers/specs/2026-10-24-ios-swiftui-design.md`。

- iOS 17+ / SwiftUI / 外部ライブラリなし
- Xcode プロジェクトは生成物: `cd ios && xcodegen generate`
- テストと CI: リポジトリ直下の `codemagic.yaml`(Codemagic)
- Web版データの移行: Web版のDevToolsで `copy(localStorage['shift-sched-events'])` → アプリの設定「クリップボードから読み込む」
- 実機配布には App Store Connect のアプリ登録 / 署名設定(bundle id `com.kom26.shift`)が別途必要
- CI: `feat/ios-*` ブランチへ push すると Codemagic の `Shift iOS test` が自動で走る(GitHub Webhook)。TestFlight 配信(`Shift iOS TestFlight`)は Codemagic で手動実行
