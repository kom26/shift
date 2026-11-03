import SwiftUI

/// 新しい端末で iCloud のデータが届くまで、操作を止めて出す画面
struct RestoringOverlay: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text("データを引き継いでいます")
                    .font(.app(17, weight: .semibold))
                Text("iCloud から予定を読み込んでいます。\nしばらくお待ちください。")
                    .font(.app(13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .transition(.opacity)
    }
}
