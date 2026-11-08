import SwiftUI

/// 新しい端末でアカウントのデータを読み込む間、または端末とアカウントのどちらを残すか選ぶ間に、操作を止めて出す画面
struct RestoringOverlay: View {
    let sync: AccountSync

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            if let info = sync.status.choice {
                choice(info)
            } else {
                VStack(spacing: 16) {
                    ProgressView().controlSize(.large)
                    Text("データを引き継いでいます")
                        .font(.app(17, weight: .semibold))
                    Text("予定を読み込んでいます。")
                        .font(.app(13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .transition(.opacity)
    }

    private func choice(_ info: SyncChoiceInfo) -> some View {
        VStack(spacing: 20) {
            Text("どちらのデータを使いますか?")
                .font(.app(19, weight: .bold))
            Text("端末とアカウントの両方に異なるデータがあります。どちらか一方のデータしか保持されません。")
                .font(.app(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 12) {
                Button { sync.resolve(.remote) } label: {
                    option(title: "アカウントのデータを使う", detail: "\(info.remoteCount) 件(この端末のデータは消えます)")
                }
                Button { sync.resolve(.local) } label: {
                    option(title: "この端末のデータを使う", detail: "\(info.localCount) 件(アカウントのデータは消えます)")
                }
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }

    private func option(title: String, detail: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.app(17, weight: .semibold)).foregroundStyle(Theme.accent)
            Text(detail).font(.app(12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent, lineWidth: 1.5))
    }
}
