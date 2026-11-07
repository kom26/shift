import Foundation

/// アップデートのお知らせの設定(Firestore の config/app)。ビルド番号で比べる
struct UpdateConfig: Equatable {
    enum Mode: String { case soft, force, none }

    /// 更新を勧めたいビルド(外部テスターなら、外部に配ったビルドの最新)
    var latestBuild: Int
    /// これより古いビルドは使えない(閉じられない画面を出す)
    var minBuild: Int
    /// 最新より古いときの出し方。ゆるい(閉じられる)・強制・なし
    var mode: Mode
    /// 更新先(なければ TestFlight を開く)
    var storeUrl: String?
}

enum UpdateAction: Equatable {
    case none, soft, force

    /// 自分のビルドと設定を比べて、何を出すか
    static func decide(build: Int, config: UpdateConfig?) -> UpdateAction {
        guard let config else { return .none }
        // 最低限より古いなら、モードにかかわらず強制
        if build < config.minBuild { return .force }
        guard build < config.latestBuild else { return .none }
        switch config.mode {
        case .none: return .none
        case .soft: return .soft
        case .force: return .force
        }
    }
}
