import AuthenticationServices
import SwiftUI

/// 設定の「アカウント」。ログインは任意で、していなくても今までどおり使える
struct AccountSection: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.colorScheme) private var scheme
    @State private var confirmDelete = false

    var body: some View {
        Section {
            if let account = auth.account {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name ?? account.email ?? "ログイン中")
                        Text("\(account.provider) でログイン中").font(.app(12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if auth.busy { ProgressView() }
                }
                Button("ログアウト") { auth.signOut() }
                Button("アカウントを削除", role: .destructive) { confirmDelete = true }
            } else {
                SignInWithAppleButton(.signIn) { request in
                    auth.prepareApple(request)
                } onCompletion: { result in
                    Task { await auth.finishApple(result) }
                }
                .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                .frame(height: 44)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                Button {
                    Task { await auth.signInWithGoogle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "g.circle.fill")
                        Text("Google でサインイン").font(.app(17, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(Color.primary)
                    .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            }
        } header: {
            Text("アカウント")
        } footer: {
            Text(auth.account == nil
                 ? "ログインすると、予定がアカウントに保存され、ほかの端末でも使えるようになります。ログインしなくても今までどおり使えます。"
                 : "アカウントを削除すると、ログイン情報が消えます。端末の中の予定は残ります。")
        }
        .alert("アカウントを削除しますか?", isPresented: $confirmDelete) {
            Button("削除", role: .destructive) { Task { await auth.deleteAccount() } }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この操作は取り消せません。")
        }
        .alert("エラー", isPresented: Binding(get: { auth.errorMessage != nil },
                                              set: { if !$0 { auth.errorMessage = nil } })) {
            Button("OK") { auth.errorMessage = nil }
        } message: {
            Text(auth.errorMessage ?? "")
        }
    }
}
