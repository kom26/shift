import SwiftUI

/// 共有カレンダーを作る。作ったあとは招待コードを見せる
struct CalendarCreateSheet: View {
    @Environment(CalendarService.self) private var service
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var made: (calendar: SharedCalendar, invite: InviteCode)?

    var body: some View {
        NavigationStack {
            Form {
                if let made {
                    InviteSection(code: made.invite)
                } else {
                    Section {
                        TextField("カレンダーの名前", text: $name)
                    } footer: {
                        Text("作ったあとに表示される招待コードを相手に送ると、参加してもらえます。")
                    }
                    if let message = service.errorMessage {
                        Section { Text(message).foregroundStyle(.red) }
                    }
                }
            }
            .navigationTitle(made == nil ? "共有カレンダーを作る" : "作成しました")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(made == nil ? "キャンセル" : "閉じる") { dismiss() }
                }
                if made == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("作成") { Task { made = await service.create(name: name) } }
                            .disabled(service.busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// 招待コードで参加する
struct CalendarJoinSheet: View {
    @Environment(CalendarService.self) private var service
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("招待コード", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("共有してくれた人から届いた招待コードを貼り付けてください。")
                }
                if let message = service.errorMessage {
                    Section { Text(message).foregroundStyle(.red) }
                }
            }
            .navigationTitle("招待コードで参加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("参加") {
                        Task { if await service.join(code: code) != nil { dismiss() } }
                    }
                    .disabled(service.busy || code.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { service.errorMessage = nil }
    }
}

/// 参加している共有カレンダーの情報。招待コードの確認と、退出
struct CalendarDetailSheet: View {
    @Environment(CalendarService.self) private var service
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let calendar: SharedCalendar
    @State private var invite: InviteCode?
    @State private var confirmLeave = false

    private var isOwner: Bool { calendar.ownerUid == auth.account?.uid }

    var body: some View {
        NavigationStack {
            Form {
                Section("招待") {
                    if let invite {
                        InviteSection(code: invite, embedded: true)
                    } else if let message = service.errorMessage {
                        Text(message).foregroundStyle(.red)
                    } else {
                        ProgressView()
                    }
                }
                if !isOwner {
                    Section {
                        Button("このカレンダーから退出", role: .destructive) { confirmLeave = true }
                    }
                }
            }
            .navigationTitle(calendar.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
            .task { invite = await service.invite(for: calendar) }
            .confirmationDialog("退出しますか?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("退出", role: .destructive) {
                    Task { await service.leave(calendar); dismiss() }
                }
            } message: {
                Text("もう一度参加するには、招待コードが必要です。")
            }
        }
        .presentationDetents([.medium])
    }
}

/// 招待コードの表示。コピーと共有ができる
private struct InviteSection: View {
    let code: InviteCode
    var embedded = false

    var body: some View {
        if embedded { content } else { Section("招待コード") { content } }
    }

    @ViewBuilder private var content: some View {
        Text(code.text)
            .font(.system(.footnote, design: .monospaced))
            .textSelection(.enabled)
        Button("コピー") { UIPasteboard.general.string = code.text }
        ShareLink(item: "シフトパレットの共有カレンダーに招待されました。アプリのメニューから「招待コードで参加」を選び、次のコードを貼り付けてください。\n\(code.text)") {
            Text("コードを送る")
        }
    }
}
