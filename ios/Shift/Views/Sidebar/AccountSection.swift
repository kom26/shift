import AuthenticationServices
import SwiftUI

/// 設定の「アカウント」。ログインは任意で、していなくても今までどおり使える
struct AccountSection: View {
    @Environment(AuthService.self) private var auth
    @Environment(AccountSync.self) private var sync
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
                if let t = sync.status.lastSync {
                    HStack {
                        Text("最後の同期")
                        Spacer()
                        Text(t.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                    }
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
                 ? "ログインすると、予定・職場・よく使う予定・記念日がアカウントに保存され、機種変更でも引き継げます。ログインしなくても今までどおり使えます。"
                 : "予定などは自動でアカウントに保存されます。アカウントを削除すると、アカウントのデータとログイン情報が消えます。端末の中の予定は残ります。")
        }
        .alert("アカウントを削除しますか?", isPresented: $confirmDelete) {
            Button("削除", role: .destructive) {
                Task {
                    // 先にアカウントのデータを消す。削除に失敗したら、端末のデータをもう一度送って元に戻す
                    await sync.eraseRemote()
                    if await !auth.deleteAccount(), let uid = auth.account?.uid {
                        await sync.start(uid: uid)
                    }
                }
            }
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
