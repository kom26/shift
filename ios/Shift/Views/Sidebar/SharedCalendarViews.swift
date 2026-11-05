import CoreImage.CIFilterBuiltins
import SwiftUI

/// 共有に出す職場・ラベルを選ぶ(複数)
struct ShareItemsSection: View {
    @Environment(Store.self) private var store
    @Binding var selection: Set<String>

    var body: some View {
        if !store.workplaces.isEmpty {
            Section("共有する職場") {
                ForEach(store.workplaces) { w in
                    row(name: w.name, color: w.color, key: ShareKey.workplace(w.id))
                }
            }
        }
        Section {
            row(name: "指定なし", color: EventLabel.noneColor, key: ShareKey.label(nil))
            ForEach(store.labels) { l in
                row(name: l.name, color: l.color, key: ShareKey.label(l.id))
            }
        } header: {
            Text("共有するラベル")
        } footer: {
            Text("選んだ職場・ラベルの予定だけが、タイトルと日時・職場名とラベル名・色だけの形で相手に見えます。給料やメモは見えません。")
        }
    }

    private func row(name: String, color: String, key: String) -> some View {
        Button {
            if selection.contains(key) { selection.remove(key) } else { selection.insert(key) }
        } label: {
            HStack(spacing: 12) {
                ColorDot(hex: color, size: 14)
                Text(name)
                Spacer()
                if selection.contains(key) { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
    }
}

extension Store {
    /// いま共有に出せる項目すべて(職場・ラベル・指定なし)
    var allShareKeys: Set<String> {
        Set(workplaces.map { ShareKey.workplace($0.id) } + labels.map { ShareKey.label($0.id) } + [ShareKey.label(nil)])
    }
}

/// 共有カレンダーを作る。作ったあとは招待(QR とリンク)を見せる
struct CalendarCreateSheet: View {
    @Environment(CalendarService.self) private var service
    @Environment(AuthService.self) private var auth
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var displayName = ""
    @State private var kind = CalendarKind.mutual
    @State private var requireApproval = false
    @State private var shared: Set<String> = []
    @State private var made: (calendar: SharedCalendar, invite: InviteCode)?
    @State private var didSetup = false

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if let made {
                    InviteSection(code: made.invite, calendarName: made.calendar.name)
                } else {
                    Section {
                        TextField("カレンダー名", text: $name)
                        TextField("相手に見える自分の名前", text: $displayName)
                    }
                    Section {
                        Picker("種類", selection: $kind) {
                            ForEach(CalendarKind.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Toggle("参加を許可制にする", isOn: $requireApproval)
                    } footer: {
                        Text(kind.detail + (requireApproval ? "\n参加を申し込んだ人は、あなたが承認するまで予定を見られません。" : ""))
                    }
                    ShareItemsSection(selection: $shared)
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
                        Button("作成") {
                            Task {
                                made = await service.create(NewCalendar(name: name, displayName: displayName, kind: kind,
                                                                        requireApproval: requireApproval,
                                                                        sharedKeys: shared.sorted()))
                            }
                        }
                        .disabled(service.busy || !canCreate)
                    }
                }
            }
            .onAppear {
                guard !didSetup else { return }
                didSetup = true
                displayName = auth.account?.name ?? ""
                shared = store.allShareKeys
                service.errorMessage = nil
            }
        }
        .presentationDetents([.large])
    }
}

/// 招待コードやリンクで参加する。内容を確認してから、名前と共有する項目を選んで参加する
struct CalendarJoinSheet: View {
    @Environment(CalendarService.self) private var service
    @Environment(AuthService.self) private var auth
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var code: String
    @State private var found: (code: InviteCode, preview: InvitePreview)?
    @State private var displayName = ""
    @State private var shared: Set<String> = []
    @State private var joined: SharedCalendar?

    init(code: String = "") {
        _code = State(initialValue: code)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let joined {
                    Section {
                        Text(joined.status == .pending
                             ? "「\(joined.name)」への参加を申し込みました。持ち主が承認すると、予定が見られるようになります。"
                             : "「\(joined.name)」に参加しました。")
                    }
                } else if let found {
                    Section {
                        LabeledContent("カレンダー", value: found.preview.calendarName)
                        if !found.preview.ownerName.isEmpty { LabeledContent("持ち主", value: found.preview.ownerName) }
                        LabeledContent("種類", value: found.preview.kind.title)
                    } footer: {
                        Text(found.preview.requireApproval ? "許可制です。持ち主が承認するまで予定は見られません。" : "")
                    }
                    Section {
                        TextField("相手に見える自分の名前", text: $displayName)
                    }
                    if found.preview.kind == .mutual {
                        ShareItemsSection(selection: $shared)
                    }
                } else {
                    Section {
                        TextField("招待コードまたはリンク", text: $code)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } footer: {
                        Text("共有してくれた人から届いた招待コードか、リンクを貼り付けてください。")
                    }
                }
                if joined == nil, let message = service.errorMessage {
                    Section { Text(message).foregroundStyle(.red) }
                }
            }
            .navigationTitle("共有カレンダーに参加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(joined == nil ? "キャンセル" : "閉じる") { dismiss() } }
                if joined == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        if let found {
                            Button("参加") {
                                Task {
                                    joined = await service.join(code: found.code, displayName: displayName,
                                                                sharedKeys: found.preview.kind == .mutual ? shared.sorted() : [])
                                }
                            }
                            .disabled(service.busy || displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                        } else {
                            Button("確認") { Task { await check() } }
                                .disabled(service.busy || code.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
            }
            .onAppear {
                service.errorMessage = nil
                displayName = auth.account?.name ?? ""
                shared = store.allShareKeys
                // リンクから開いたときは、コードが入った状態で始まるので、そのまま内容を確認する
                if !code.isEmpty, found == nil { Task { await check() } }
            }
        }
        .presentationDetents([.large])
    }

    private func check() async {
        if let result = await service.preview(code: code) { found = result }
    }
}

/// 参加している共有カレンダーの情報。招待、参加者、自分の共有する項目、退出
struct CalendarDetailSheet: View {
    @Environment(CalendarService.self) private var service
    @Environment(AuthService.self) private var auth
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let calendar: SharedCalendar
    @State private var invite: InviteCode?
    @State private var members: [CalendarMember] = []
    @State private var displayName = ""
    @State private var shared: Set<String> = []
    @State private var confirmLeave = false
    @State private var removing: CalendarMember?
    @State private var loaded = false
    @State private var savedNote = false

    private var uid: String? { auth.account?.uid }
    private var isOwner: Bool { calendar.ownerUid == uid }
    private var canShareMine: Bool { calendar.kind == .mutual || isOwner }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("種類", value: calendar.kind.title)
                    if calendar.requireApproval { LabeledContent("参加", value: "許可制") }
                }
                if calendar.status == .pending {
                    Section { Text("承認待ちです。持ち主が承認すると、予定が見られるようになります。") }
                } else {
                    if isOwner {
                        if let invite {
                            InviteSection(code: invite, calendarName: calendar.name)
                        } else if let message = service.errorMessage {
                            Section("招待") { Text(message).foregroundStyle(.red) }
                        } else {
                            Section("招待") { ProgressView() }
                        }
                    }
                    Section("参加者") {
                        ForEach(members) { m in memberRow(m) }
                    }
                    Section {
                        TextField("相手に見える自分の名前", text: $displayName)
                    }
                    if canShareMine {
                        ShareItemsSection(selection: $shared)
                    }
                    Section {
                        Button("自分の設定を保存") {
                            Task {
                                if await service.updateMine(in: calendar, displayName: displayName,
                                                            sharedKeys: canShareMine ? shared.sorted() : []) {
                                    savedNote = true
                                    members = await service.members(of: calendar) ?? members
                                }
                            }
                        }
                        .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                    } footer: {
                        if savedNote { Text("保存しました。") }
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
            .task { await load() }
            .confirmationDialog("退出しますか?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("退出", role: .destructive) {
                    Task { await service.leave(calendar); dismiss() }
                }
            } message: {
                Text("もう一度参加するには、招待が必要です。")
            }
            .confirmationDialog("\(removing?.displayName ?? "")さんを削除しますか?", isPresented: Binding(
                get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("削除", role: .destructive) {
                    if let m = removing {
                        Task {
                            if await service.remove(m, from: calendar) { members.removeAll { $0.id == m.id } }
                        }
                    }
                    removing = nil
                }
            } message: {
                Text("削除された人は、このカレンダーの予定が見られなくなります。")
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func memberRow(_ m: CalendarMember) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(m.displayName.isEmpty ? "(名前なし)" : m.displayName)
                if m.isOwner {
                    Text("持ち主").font(.footnote).foregroundStyle(.secondary)
                } else if m.status == .pending {
                    Text("承認待ち").font(.footnote).foregroundStyle(.orange)
                }
            }
            Spacer()
            if isOwner, !m.isOwner {
                if m.status == .pending {
                    Button("承認") {
                        Task {
                            if await service.approve(m, in: calendar) {
                                members = await service.members(of: calendar) ?? members
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                }
                Button(m.status == .pending ? "却下" : "削除", role: .destructive) { removing = m }
                    .buttonStyle(.borderless)
            }
        }
    }

    private func load() async {
        guard !loaded else { return }
        loaded = true
        guard calendar.status == .active else { return }
        if isOwner { invite = await service.invite(for: calendar) }
        members = await service.members(of: calendar) ?? []
        if let me = members.first(where: { $0.id == uid }) {
            displayName = me.displayName
            shared = Set(me.sharedKeys)
        }
    }
}

/// 招待の表示。QR(画像で保存できる)、リンク、コード
private struct InviteSection: View {
    let code: InviteCode
    let calendarName: String
    @State private var saved = false

    var body: some View {
        Section("招待") {
            if let image = QRCode.image(for: code.link?.absoluteString ?? code.text) {
                HStack {
                    Spacer()
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .accessibilityLabel("招待の QR コード")
                    Spacer()
                }
                .padding(.vertical, 6)
                Button(saved ? "写真に保存しました" : "QR コードを画像として保存") {
                    UIImageWriteToSavedPhotosAlbum(QRCode.padded(image), nil, nil, nil)
                    saved = true
                }
                .disabled(saved)
            }
            if let link = code.link {
                ShareLink(item: link, message: Text("シフトパレットの共有カレンダー「\(calendarName)」に招待されました。")) {
                    Label("招待リンクを送る", systemImage: "square.and.arrow.up")
                }
            }
            Text(code.text)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
            Button("コードをコピー") { UIPasteboard.general.string = code.text }
        }
    }
}

enum QRCode {
    /// 文字から QR コードの画像を作る(拡大してもにじまないよう、整数倍に大きくする)
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// 保存用。白い余白(クワイエットゾーン)をつけて、読み取りやすくする
    static func padded(_ image: UIImage, margin: CGFloat = 40) -> UIImage {
        let size = CGSize(width: image.size.width + margin * 2, height: image.size.height + margin * 2)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            image.draw(at: CGPoint(x: margin, y: margin))
        }
    }
}
