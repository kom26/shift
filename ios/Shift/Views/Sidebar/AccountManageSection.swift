import SwiftUI

/// 名前とアバターの画面の一番下に置く、ログアウトとアカウントの削除
struct AccountManageSection: View {
    @Environment(AuthService.self) private var auth
    @Environment(AccountSync.self) private var sync
    @Environment(CalendarService.self) private var service
    @Environment(SharedViewState.self) private var sharedView
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var ownerBlocked = false
    @State private var working = false
    @State private var failed = false

    private var uid: String? { auth.account?.uid }
    /// 見せるだけのカレンダーの持ち主(先にカレンダーを削除してもらう)。相互に共有するカレンダーは、退出すれば済む
    private var owned: [SharedCalendar] { service.calendars.filter { $0.kind == .oneway && $0.ownerUid == uid } }
    private var joined: [SharedCalendar] { service.calendars.filter { !($0.kind == .oneway && $0.ownerUid == uid) } }

    var body: some View {
        Section {
            Button("ログアウト") {
                auth.signOut()
                dismiss()
            }
            Button("アカウントを削除", role: .destructive) {
                if owned.isEmpty { confirmDelete = true } else { ownerBlocked = true }
            }
            .disabled(working)
            .alert("アカウントを削除しますか?", isPresented: $confirmDelete) {
                Button("削除", role: .destructive) { Task { await deleteAccount() } }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text(joined.isEmpty
                     ? "この操作は取り消せません。"
                     : "参加している共有カレンダー(\(joined.count)件)から退会して、アカウントを削除します。この操作は取り消せません。")
            }
            if working { HStack(spacing: 8) { ProgressView(); Text("削除しています…").foregroundStyle(.secondary) } }
            if failed {
                Text("共有カレンダーから退会できませんでした。通信を確認して、もう一度お試しください。")
                    .font(.footnote).foregroundStyle(.red)
            }
        } footer: {
            Text("アカウントを削除すると、アカウントのデータとログイン情報が消えます。端末の中の予定は残ります。参加している共有カレンダーからは、自動で退会します。")
        }
        .alert("持ち主の共有カレンダーがあります", isPresented: $ownerBlocked) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("見せるだけの共有カレンダー「\(owned.map(\.name).joined(separator: "」「"))」の持ち主のままでは、アカウントを削除できません。先に、そのカレンダーを削除してください。")
        }
    }

    private func deleteAccount() async {
        working = true
        failed = false
        defer { working = false }
        // 参加している共有カレンダーから、先に退会する(連動した誕生日も消える)
        for cal in joined {
            if sharedView.calendar?.id == cal.id { sharedView.close() }
            await sharedView.removeMyLinkedBirthday(in: cal.id)
            await service.leave(cal)
        }
        guard service.calendars.allSatisfy({ $0.kind == .oneway && $0.ownerUid == uid }) else {
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
