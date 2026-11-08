import AuthenticationServices
import SwiftUI

/// 設定の「アカウント」。ログインは任意で、していなくても今までどおり使える
struct AccountSection: View {
    @Environment(AuthService.self) private var auth
    @Environment(AccountSync.self) private var sync
    @Environment(ProfileSettings.self) private var profile
    @Environment(\.colorScheme) private var scheme
    @State private var editingProfile = false

    private var errorShown: Binding<Bool> {
        Binding(get: { auth.errorMessage != nil }, set: { if !$0 { auth.errorMessage = nil } })
    }

    var body: some View {
        Section {
            if let account = auth.account {
                // 名前(とアバター)をタップすると、アプリの中での表示を直せる
                Button { editingProfile = true } label: {
                    let shown = profile.displayName(for: account)
                    HStack(spacing: 12) {
                        UserAvatar(uid: account.uid, name: shown, avatar: profile.avatar, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shown.isEmpty ? "ログイン中" : shown).foregroundStyle(Color.primary)
                            Text("\(account.provider) でログイン中").font(.app(12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if auth.busy { ProgressView() }
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .sheet(isPresented: $editingProfile) { ProfileEditSheet() }
                .alert("エラー", isPresented: errorShown) {
                    Button("OK") { auth.errorMessage = nil }
                } message: {
                    Text(auth.errorMessage ?? "")
                }
                // ログインしているあいだは、いつも出す(まだ同期していなければ、その旨)
                HStack {
                    Text("最後の同期")
                    Spacer()
                    Text(sync.status.lastSync.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "まだ同期していません")
                        .foregroundStyle(.secondary)
                }
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
                .alert("エラー", isPresented: errorShown) {
                    Button("OK") { auth.errorMessage = nil }
                } message: {
                    Text(auth.errorMessage ?? "")
                }
            }
        } header: {
            Text("アカウント")
        } footer: {
            if auth.account == nil {
                Text("アカウント登録かログインすると、予定などがアカウントに保存され、機種変更でも引き継げます。「共有カレンダー」と「画像から予定追加」は、アカウントが必要です。")
            }
        }
    }
}
