import SwiftUI

/// 名前とアバターの画面の一番下に置く、ログアウトとアカウントの削除
struct AccountManageSection: View {
    @Environment(AuthService.self) private var auth
    @Environment(AccountSync.self) private var sync
    @Environment(CalendarService.self) private var service
    @Environment(SharedViewState.self) private var sharedView
    @Environment(Store.self) private var store
    @Environment(ProfileSettings.self) private var profile
    @Environment(\.dismiss) private var dismiss
    @State private var confirmLogout = false
    @State private var checkingLogout = false
    /// 保存できていない変更がある(届いたと確かめられた最後の時刻つき)
    @State private var unsent: LogoutCheck?
    @State private var confirmDelete = false
    @State private var working = false
    @State private var failed = false

    private var uid: String? { auth.account?.uid }
    /// 見せるだけのカレンダーの持ち主(先にカレンダーを削除してもらう)。相互に共有するカレンダーは、退出すれば済む
    private var owned: [SharedCalendar] { service.calendars.filter { $0.kind == .oneway && $0.ownerUid == uid } }
    private var joined: [SharedCalendar] { service.calendars.filter { !($0.kind == .oneway && $0.ownerUid == uid) } }

    var body: some View {
        Section {
            Button("ログアウト") { confirmLogout = true }
                .disabled(checkingLogout || working)
                .alert("ログアウトしますか?", isPresented: $confirmLogout) {
                    Button("ログアウト", role: .destructive) { Task { await tryLogout() } }
                    Button("キャンセル", role: .cancel) {}
                } message: {
                    Text("この端末の予定や設定は、消えます。もう一度ログインすると、アカウントに保存したデータが戻ります。ログアウトの前に、すべてのデータが保存されているか確認します。")
                }
                .alert("保存できていないデータがあります", isPresented: Binding(get: { unsent != nil }, set: { if !$0 { unsent = nil } })) {
                    Button("もう一度確認") { Task { await tryLogout() } }
                    Button("それでもログアウト", role: .destructive) { performLogout() }
                    Button("キャンセル", role: .cancel) {}
                } message: {
                    Text(unsentMessage)
                }
            if checkingLogout { HStack(spacing: 8) { ProgressView(); Text("保存されているか確認しています…").foregroundStyle(.secondary) } }
            Button("アカウントを削除", role: .destructive) { confirmDelete = true }
            .disabled(working)
            .alert("アカウントを削除しますか?", isPresented: $confirmDelete) {
                Button("削除", role: .destructive) { Task { await deleteAccount() } }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text(confirmMessage)
            }
            if working { HStack(spacing: 8) { ProgressView(); Text("削除しています…").foregroundStyle(.secondary) } }
            if failed {
                Text("共有カレンダーの削除・退会ができませんでした。通信を確認して、もう一度お試しください。")
                    .font(.footnote).foregroundStyle(.red)
            }
        } footer: {
            Text("アカウント削除すると共有カレンダーは全て退出し、見せるだけの共有カレンダーやバックアップが全て削除されます。端末の予定(自分のカレンダー)は残ります。")
        }
    }

    private var unsentMessage: String {
        var text = "通信できる場所で、もう一度お試しください。"
        if case .unsent(let at?)? = unsent {
            text = at.formatted(date: .abbreviated, time: .shortened) + " 以降の変更は、アカウントに保存されていません。\n" + text
        }
        return text + "\nこのままログアウトすると、保存されていない変更は消えます。"
    }

    /// ログアウトの前に、すべて保存されているか確かめる。確かめられたら、端末を消してログアウトする
    private func tryLogout() async {
        checkingLogout = true
        unsent = nil
        let check = await sync.prepareLogout()
        checkingLogout = false
        if check == .ready { performLogout() } else { unsent = check }
    }

    /// ログアウトして、端末のデータと設定をまっさらにする。ログインし直すと、アカウントから戻る
    private func performLogout() {
        guard auth.signOut() else { return }
        sync.eraseLocalMemo()
        sharedView.close()
        store.wipeLocalData()
        profile.reload()
        UserDefaults.standard.removeObject(forKey: "pending-invites")
        WidgetSync.publish(store: store)
        // 端末のアラームも外す(記録がなくなったので、残りは「解除された」と扱われる)
        Task { await AlarmService.shared.refresh(store: store) }
        dismiss()
    }

    private var confirmMessage: String {
        var lines: [String] = []
        if !owned.isEmpty {
            lines.append("見せるだけの共有カレンダー「" + owned.map(\.name).joined(separator: "」「") + "」は削除されます。")
        }
        if !joined.isEmpty { lines.append("参加している共有カレンダー(\(joined.count)件)からは、退会します。") }
        lines.append("この操作は取り消せません。")
        return lines.joined(separator: "\n")
    }

    private func deleteAccount() async {
        working = true
        failed = false
        defer { working = false }
        // 見せるだけの共有カレンダーは、削除する(参加者には、削除されたことが知らされる)
        for cal in owned {
            if sharedView.calendar?.id == cal.id { sharedView.close() }
            if await !service.delete(cal) {
                failed = true
                return
            }
        }
        // 参加している共有カレンダーから、先に退会する(連動した誕生日も消える)
        for cal in joined {
            if sharedView.calendar?.id == cal.id { sharedView.close() }
            await sharedView.removeMyLinkedBirthday(in: cal.id)
            await service.leave(cal)
        }
        guard service.calendars.isEmpty else {
            failed = true
            return
        }
        // 次にアカウントのデータを消す。削除に失敗したら、端末のデータをもう一度送って元に戻す
        await sync.eraseRemote()
        if await !auth.deleteAccount(), let uid = auth.account?.uid {
            await sync.start(uid: uid)
        }
    }
}
