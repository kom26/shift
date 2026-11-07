import FirebaseFirestore
import Observation
import SwiftUI

/// 起動したときと、アプリに戻ったときに、Firestore の設定を読んで、更新のお知らせを出すか決める
@MainActor
@Observable
final class UpdateChecker {
    private(set) var action: UpdateAction = .none
    private(set) var storeUrl: String?
    /// 「あとで」で閉じたか(アプリを閉じるまで。次に起動したときは、また出る)
    private(set) var dismissed = false

    static var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    var showsSoft: Bool { action == .soft && !dismissed }
    var showsForce: Bool { action == .force }

    func check() async {
        guard let snap = try? await Firestore.firestore().collection("config").document("app").getDocument(),
              let data = snap.data() else { return }
        let config = UpdateConfig(
            latestBuild: (data["latestBuild"] as? NSNumber)?.intValue ?? 0,
            minBuild: (data["minBuild"] as? NSNumber)?.intValue ?? 0,
            mode: UpdateConfig.Mode(rawValue: data["mode"] as? String ?? "") ?? .none,
            storeUrl: data["storeUrl"] as? String)
        storeUrl = config.storeUrl
        action = UpdateAction.decide(build: Self.currentBuild, config: config)
    }

    func dismiss() { dismissed = true }

    /// 更新先を開く(App Store のアドレスが設定にあればそこへ、なければ TestFlight)
    func openStore() {
        let candidates = [storeUrl, "itms-beta://", "https://testflight.apple.com/"].compactMap { $0 }.compactMap(URL.init(string:))
        guard let url = candidates.first else { return }
        UIApplication.shared.open(url) { ok in
            if !ok, let fallback = URL(string: "https://testflight.apple.com/") { UIApplication.shared.open(fallback) }
        }
    }
}

/// 更新のお知らせ。ゆるいときは閉じられるカード、強制のときは閉じられない全画面
struct UpdateNoticeOverlay: View {
    let checker: UpdateChecker

    var body: some View {
        ZStack {
            if checker.showsForce {
                forceScreen
                    .transition(.opacity)
            } else if checker.showsSoft {
                Color.black.opacity(0.35).ignoresSafeArea()
                softCard
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: checker.showsSoft)
        .animation(.snappy, value: checker.showsForce)
    }

    private var icon: some View {
        Image(systemName: "arrow.down.circle.fill")
            .font(.system(size: 34))
            .foregroundStyle(Theme.accent)
    }

    private var softCard: some View {
        VStack(spacing: 8) {
            icon.padding(.bottom, 4)
            Text("新しいバージョンがあります").font(.app(17, weight: .bold))
            Text("更新すると、新しい機能や修正が使えます。TestFlight を開いて更新してください。")
                .font(.app(13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { checker.openStore() } label: {
                Text("更新する").font(.app(16, weight: .bold)).foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 46).background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 10)
            Button("あとで") { checker.dismiss() }
                .font(.app(15)).frame(minHeight: 40)
        }
        .padding(20)
        .frame(maxWidth: 320)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        .padding(.horizontal, 30)
    }

    private var forceScreen: some View {
        VStack(spacing: 10) {
            icon.scaleEffect(1.5).padding(.bottom, 14)
            Text("アップデートが必要です").font(.app(20, weight: .bold))
            Text("このバージョンはもう使えません。TestFlight を開いて、最新のバージョンに更新してください。")
                .font(.app(14)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { checker.openStore() } label: {
                Text("更新する").font(.app(17, weight: .bold)).foregroundStyle(Theme.onAccent)
                    .frame(width: 220, height: 50).background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}
