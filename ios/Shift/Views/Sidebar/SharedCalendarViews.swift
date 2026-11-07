import CoreImage.CIFilterBuiltins
import PhotosUI
import SwiftUI

/// 共有に出す勤務予定・ラベルを選ぶ(複数)。1 つの見出しにまとめる
struct ShareItemsSection: View {
    @Environment(Store.self) private var store
    @Binding var selection: Set<String>
    /// true のとき、1 つも選ばないと先へ進めないことを、下の説明で伝える
    var required = false

    var body: some View {
        Section {
            ForEach(store.workplaces) { w in
                row(name: w.name, color: w.color, key: ShareKey.workplace(w.id))
            }
            row(name: "指定なし", color: EventLabel.noneColor, key: ShareKey.label(nil))
            ForEach(store.labels) { l in
                row(name: l.name, color: l.color, key: ShareKey.label(l.id))
            }
        } header: {
            HStack {
                Text("共有する勤務予定・ラベル")
                Spacer()
                // 作るときは、1 つも選んでいない間だけ、右に必須を出す
                if required && selection.isEmpty {
                    Text("1つ以上選択必須").foregroundStyle(.red)
                }
            }
        } footer: {
            Text("選んだ勤務予定・ラベルの予定だけが、タイトルと日時・職場名とラベル名・色だけの形で相手に見えます。給料やメモは見えません。")
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
                // 共有に出せる予定の数(日付のある予定)
                Text("\(store.shareEventCount(key))件").font(.app(13)).foregroundStyle(.secondary)
                if selection.contains(key) { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
    }
}

extension Store {
    /// その項目(職場・ラベル)に入っている、共有に出せる予定の数(日付のある予定)
    func shareEventCount(_ key: String) -> Int {
        events.filter { $0.placed && $0.startDate != nil && ShareKey.of($0, store: self) == key }.count
    }

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
    @Environment(SharedViewState.self) private var sharedView
    @Environment(ProfileSettings.self) private var profile
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon = CalendarIcon.defaultName
    @State private var displayName = ""
    /// この共有カレンダーでの自分のアバター。最初は、アカウントで決めたもの(写真があれば写真、なければ名前の頭文字)
    @State private var avatar = ""
    @State private var kind = CalendarKind.mutual
    @State private var requireApproval = false
    @State private var shared: Set<String> = []
    @State private var made: (calendar: SharedCalendar, invite: InviteCode)?
    @State private var didSetup = false

    /// 名前が 2 つとも入っていて、共有する勤務予定・ラベルが 1 つ以上選ばれている
    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !displayName.trimmingCharacters(in: .whitespaces).isEmpty
            && !shared.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if let made {
                    InviteSection(code: made.invite, calendarName: made.calendar.name)
                } else {
                    Section("カレンダー名") {
                        CalendarNameField(name: $name, icon: $icon)
                    }
                    Section("相手に見える自分の名前") {
                        HStack(spacing: 12) {
                            AvatarEditCircle(avatar: $avatar, uid: auth.account?.uid ?? "", name: displayName)
                            TextField("名前", text: $displayName)
                        }
                    }
                    Section {
                        TwoWayPicker("種類", selection: $kind, first: (CalendarKind.oneway.title, CalendarKind.oneway), second: (CalendarKind.mutual.title, CalendarKind.mutual))
                        Toggle("参加を許可制にする", isOn: $requireApproval)
                    } footer: {
                        Text(kind.detail + (requireApproval ? "\n参加を申し込んだ人は、あなたが承認するまで予定を見られません。" : ""))
                    }
                    ShareItemsSection(selection: $shared, required: true)
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
                                                                        sharedKeys: shared.sorted(), icon: icon, avatar: avatar))
                                // 作ったカレンダーを開いておく(シートを閉じると、そのカレンダーが見える)
                                if let made { await sharedView.open(made.calendar) }
                            }
                        }
                        .disabled(service.busy || !canCreate)
                    }
                }
            }
            .onAppear {
                guard !didSetup else { return }
                didSetup = true
                displayName = profile.displayName(for: auth.account)
                avatar = profile.avatar
                // 共有する勤務予定・ラベルは、最初はどれも選ばない(間違って見せないよう、1 つ以上を自分で選ぶ)
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
    @Environment(ProfileSettings.self) private var profile
    @Environment(\.dismiss) private var dismiss
    @State var code: String
    @State private var found: (code: InviteCode, preview: InvitePreview)?
    @State private var displayName = ""
    /// この共有カレンダーでの自分のアバター。最初は、アカウントで決めたもの
    @State private var avatar = ""
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
                    Section("相手に見える自分の名前") {
                        HStack(spacing: 12) {
                            AvatarEditCircle(avatar: $avatar, uid: auth.account?.uid ?? "", name: displayName)
                            TextField("名前", text: $displayName)
                        }
                    }
                    if found.preview.kind == .mutual {
                        ShareItemsSection(selection: $shared)
                    }
                } else {
                    Section {
                        TextField("招待リンク", text: $code)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } footer: {
                        Text("共有してくれた人から届いた招待リンクを貼り付けてください。")
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
                                                                sharedKeys: found.preview.kind == .mutual ? shared.sorted() : [],
                                                                avatar: avatar)
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
                displayName = profile.displayName(for: auth.account)
                avatar = profile.avatar
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
    @Environment(SharedViewState.self) private var sharedView
    @Environment(SharedPublisher.self) private var publisher
    @Environment(\.dismiss) private var dismiss
    let calendar: SharedCalendar
    @State private var confirmDelete = false
    @State private var invite: InviteCode?
    @State private var members: [CalendarMember] = []
    @State private var displayName = ""
    @State private var shared: Set<String> = []
    @State private var confirmLeave = false
    @State private var removing: CalendarMember?
    @State private var loaded = false
    @State private var actionError: String?
    @State private var avatar = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var cropTarget: AvatarCropTarget?
    /// 頭文字の背景色の選択を開いているか(選択中の頭文字をもう一度タップで開く)
    @State private var showBackgroundColors = false
    /// 持ち主が変えられる、カレンダーの名前・アイコン・許可制
    @State private var calName = ""
    @State private var calIcon = CalendarIcon.defaultName
    @State private var calApproval = false
    @State private var confirmOpenApproval = false
    /// 共有のしかた(手動なら、確認してから共有する)
    @State private var shareManual = false
    @State private var reviewing = false
    @State private var confirmAuto = false
    @State private var approvalConfirmed = false
    @State private var autoConfirmed = false

    private var uid: String? { auth.account?.uid }
    private var isOwner: Bool { calendar.ownerUid == uid }
    private var canShareMine: Bool { calendar.kind == .mutual || isOwner }

    var body: some View {
        NavigationStack {
            dialogs(
                Form {
                    ownerSection
                    memberSections
                    dangerSection
                }
                .navigationTitle(calendar.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                if calendar.status == .active {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { Task { await save() } }
                            .disabled(service.busy || displayName.trimmingCharacters(in: .whitespaces).isEmpty
                                      || (isOwner && calName.trimmingCharacters(in: .whitespaces).isEmpty))
                    }
                }
            }
            .task { await load() }
            .onChange(of: service.calendars) { _, list in
                // 承認待ちの画面を開いている間に承認されたら、そのまま共有カレンダーを開く
                if calendar.status == .pending, let c = list.first(where: { $0.id == calendar.id }), c.status == .active {
                    dismiss()
                    Task { await sharedView.open(c) }
                }
            }
            )
        }
        .presentationDetents([.large])
    }

    /// 持ち主は、作るときと同じ項目(名前・アイコン・許可制)をここから変えられる
    @ViewBuilder
    private var ownerSection: some View {
                if isOwner && calendar.status == .active {
                    // 作るときと同じ項目を、持ち主はここから変えられる
                    Section("カレンダー名") {
                        CalendarNameField(name: $calName, icon: $calIcon)
                    }
                    Section {
                        LabeledContent("種類", value: calendar.kind.title)
                        Toggle("参加を許可制にする", isOn: $calApproval)
                    } footer: {
                        Text(calApproval
                             ? "参加を申し込んだ人は、あなたが承認するまで予定を見られません。"
                             : "招待を受け取った人は、すぐに参加できます。")
                    }
                } else {
                    Section {
                        LabeledContent("種類", value: calendar.kind.title)
                        if calendar.requireApproval { LabeledContent("参加", value: "許可制") }
                    }
                }
    }

    /// 承認待ちの案内、招待、参加者、自分の名前・アバター、共有のしかた
    @ViewBuilder
    private var memberSections: some View {
                if calendar.status == .pending {
                    Section { Text("承認待ちです。持ち主が承認すると、予定が見られるようになります。") }
                } else {
                    if isOwner {
                        if let invite {
                            InviteSection(code: invite, calendarName: calendar.name) {
                                if let renewed = await service.reissueInvite(for: calendar) { self.invite = renewed }
                            }
                        } else if let message = service.errorMessage {
                            Section("招待") { Text(message).foregroundStyle(.red) }
                        } else {
                            Section("招待") { ProgressView() }
                        }
                    }
                    Section("参加者") {
                        ForEach(members) { m in memberRow(m) }
                    }
                    Section("相手に見える自分の名前") {
                        TextField("名前", text: $displayName)
                    }
                    Section {
                        avatarPicker
                    } header: {
                        Text("アバター")
                    } footer: {
                        Text("この共有カレンダーの中で、あなたの予定のそばに表示されます。写真は正方形に切り取って丸く表示します。")
                    }
                    SharedAnniversarySection(
                        calendar: calendar, canWrite: canShareMine,
                        names: Dictionary(members.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a }),
                        myUid: uid, displayName: displayName)
                    if canShareMine {
                        shareModeSection
                        ShareItemsSection(selection: $shared)
                    }
                }
    }

    @ViewBuilder
    private var dangerSection: some View {
                if !isOwner {
                    Section {
                        Button("このカレンダーから退出", role: .destructive) { confirmLeave = true }
                    }
                } else {
                    Section {
                        Button("このカレンダーを削除", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("参加者の画面からも消えます。共有カレンダーの中で作った予定も消えます。それぞれの元の予定は消えません。")
                    }
                }
    }

    /// 確認のダイアログ(式が長くなりすぎて型が決まらなくなるので、本体から分けてある)
    private func dialogs<Content: View>(_ content: Content) -> some View {
        content
            .alert("削除しますか?", isPresented: $confirmDelete) {
                Button("削除", role: .destructive) { Task { await deleteCalendar() } }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("「\(calendar.name)」を削除します。この操作は取り消せません。")
            }
            .alert("許可制をやめますか?", isPresented: $confirmOpenApproval) {
                Button("許可して保存") {
                    approvalConfirmed = true
                    Task { await save() }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("申請中の\(pendingCount)人は、全員参加が許可されます。")
            }
            .alert("自動に切り替えますか?", isPresented: $confirmAuto) {
                Button("切り替えて共有する") {
                    autoConfirmed = true
                    Task { await save() }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("まだ共有していない\(publisher.pendingCount(for: calendar.id))件の変更が、すぐに共有されます。")
            }
            .sheet(isPresented: $reviewing) { ShareReviewSheet(calendar: calendar) }
            .alert("できませんでした", isPresented: Binding(
                get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
                Button("OK") { actionError = nil }
            } message: {
                Text(actionError ?? "")
            }
            .confirmationDialog("退出しますか?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("退出", role: .destructive) {
                    Task {
                        if sharedView.calendar?.id == calendar.id { sharedView.close() }
                        await sharedView.removeMyLinkedBirthday(in: calendar.id)
                        await service.leave(calendar)
                        dismiss()
                    }
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

    /// 頭文字の状態か(絵文字や写真でなければ)。このとき、背景の色を選べる
    private var isInitialMode: Bool { avatar.isEmpty || UserAvatar.customBackground(avatar) != nil }

    /// 頭文字の丸の背景(自分で選んでいなければ、自動の色)
    private var initialBackground: String { UserAvatar.customBackground(avatar) ?? UserAvatar.color(for: uid ?? "") }

    private var avatarPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                initialCell
                photoCell
                Spacer(minLength: 0)
            }
            if isInitialMode && showBackgroundColors {
                VStack(alignment: .leading, spacing: 6) {
                    Text("頭文字の背景の色").font(.app(12)).foregroundStyle(.secondary)
                    backgroundRow
                }
            }
        }
        .padding(.vertical, 4)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                // 写真を選んだら、アイコンにする範囲を合わせる画面を開く
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    cropTarget = AvatarCropTarget(image: image)
                } else {
                    actionError = "写真を読み込めませんでした"
                }
                photoItem = nil
            }
        }
        .sheet(item: $cropTarget) { target in
            AvatarCropSheet(image: target.image) { square in
                if let encoded = AvatarPhoto.encode(square: square) { avatar = encoded }
            }
        }
    }

    /// 名前の頭文字。タップすると頭文字に切り替わり、背景の色を選べる
    private var initialCell: some View {
        Button {
            if isInitialMode {
                // 頭文字を選んでいる状態でもう一度タップすると、背景の色を選べる(もう一度で閉じる)
                withAnimation(.snappy) { showBackgroundColors.toggle() }
            } else {
                avatar = ""
                showBackgroundColors = false
            }
        } label: {
            UserAvatar(uid: uid ?? "", name: displayName, avatar: isInitialMode ? avatar : "", size: 48)
                .overlay(Circle().stroke(Theme.accent, lineWidth: isInitialMode ? 3 : 0).padding(-3))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("名前の頭文字")
        .accessibilityAddTraits(isInitialMode ? .isSelected : [])
    }

    /// 写真から選ぶ。選んだ写真があれば、それを丸く見せる
    private var photoCell: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            Group {
                if AvatarPhoto.isPhoto(avatar) {
                    UserAvatar(uid: uid ?? "", name: displayName, avatar: avatar, size: 48)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(Color(.tertiarySystemFill)))
                }
            }
            .overlay(Circle().stroke(Theme.accent, lineWidth: AvatarPhoto.isPhoto(avatar) ? 3 : 0).padding(-3))
        }
        .accessibilityLabel("写真から選ぶ")
    }

    /// 背景の色。最初の丸は自動(持ち主ごとに決まる色)、最後は好きな色
    private var backgroundRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                swatch(hex: UserAvatar.color(for: uid ?? ""), selected: avatar.isEmpty, label: "自動") { avatar = "" }
                ForEach(UserAvatar.backgroundChoices, id: \.self) { hex in
                    swatch(hex: hex, selected: UserAvatar.customBackground(avatar) == hex, label: hex) {
                        avatar = UserAvatar.backgroundPrefix + hex
                    }
                }
                ColorPicker("好きな色", selection: Binding(
                    get: { Color(hex: initialBackground) },
                    set: { avatar = UserAvatar.backgroundPrefix + $0.toHex() }), supportsOpacity: false)
                    .labelsHidden()
            }
            .padding(5)
        }
    }

    private func swatch(hex: String, selected: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle().fill(Color(hex: hex))
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(Color.primary, lineWidth: selected ? 2 : 0).padding(-3))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func memberRow(_ m: CalendarMember) -> some View {
        HStack {
            UserAvatar(uid: m.id, name: m.displayName, avatar: m.avatar, size: 30)
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

    private var pendingCount: Int { members.filter { $0.status == .pending }.count }

    /// 共有のしかた。自動は、予定を変えるとすぐ共有。手動は、確認してから共有する
    @ViewBuilder
    private var shareModeSection: some View {
        Section {
            TwoWayPicker("共有のしかた", selection: $shareManual, first: ("自動", false), second: ("手動(確認してから)", true))
            // 手動に切り替えて保存したあとに、確認を開ける
            if shareManual && calendar.myShareManual {
                Button { reviewing = true } label: {
                    HStack {
                        Text("共有の内容を確認する").foregroundStyle(Theme.accent).fontWeight(.semibold)
                        Spacer()
                        let n = publisher.pendingCount(for: calendar.id)
                        if n > 0 {
                            Text("\(n)")
                                .font(.app(13, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .frame(minWidth: 22, minHeight: 22)
                                .background(Color.red, in: Capsule())
                        }
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
            }
        } header: {
            Text("共有のしかた")
        } footer: {
            Text(shareManual
                 ? "予定を入れても、すぐには共有されません。「共有の内容を確認する」で、新しく共有される予定と、共有から消える予定をカレンダーで見て、よければ共有します。確認するまで、相手には前回の内容のまま見えます。"
                 : "予定を入れたり直したりすると、すぐに相手のカレンダーに反映されます。")
        }
    }

    /// 保存する。許可制をやめるとき、申請中の人がいれば、全員許可されることを先に確かめる
    private func save() async {
        if isOwner, calendar.requireApproval, !calApproval, pendingCount > 0, !approvalConfirmed {
            confirmOpenApproval = true
            return
        }
        // 手動から自動へ切り替えると、確認を待っている変更が、すぐ共有される
        if calendar.myShareManual, !shareManual, publisher.pendingCount(for: calendar.id) > 0, !autoConfirmed {
            confirmAuto = true
            return
        }
        await performSave()
    }

    /// カレンダーの設定(持ち主だけ)と自分の設定を保存して、そのカレンダーを開く
    private func performSave() async {
        if isOwner,
           calName != calendar.name || calIcon != calendar.icon || calApproval != calendar.requireApproval {
            guard await service.updateCalendar(calendar, name: calName, icon: calIcon, requireApproval: calApproval) else {
                actionError = service.errorMessage ?? "保存できませんでした"
                return
            }
        }
        let ok = await service.updateMine(in: calendar, displayName: displayName,
                                          sharedKeys: canShareMine ? shared.sorted() : [], avatar: avatar,
                                          shareManual: canShareMine ? shareManual : false)
        guard ok else {
            actionError = service.errorMessage ?? "保存できませんでした"
            return
        }
        let updated = service.calendars.first { $0.id == calendar.id } ?? calendar
        dismiss()
        await sharedView.open(updated)
    }

    private func deleteCalendar() async {
        if sharedView.calendar?.id == calendar.id { sharedView.close() }
        if await service.delete(calendar) {
            dismiss()
        } else {
            actionError = service.errorMessage ?? "削除できませんでした"
        }
    }

    private func load() async {
        guard !loaded else { return }
        loaded = true
        calName = calendar.name
        calIcon = calendar.icon
        calApproval = calendar.requireApproval
        guard calendar.status == .active else { return }
        if isOwner { invite = await service.invite(for: calendar) }
        members = await service.members(of: calendar) ?? []
        if let me = members.first(where: { $0.id == uid }) {
            displayName = me.displayName
            shared = Set(me.sharedKeys)
            avatar = me.avatar
            shareManual = me.shareManual
        }
    }
}

/// 招待の表示。QR(画像で保存できる)とリンク
private struct InviteSection: View {
    let code: InviteCode
    let calendarName: String
    /// 招待を作り直す(いまのリンク・QR は使えなくなる)。nil なら、メニューに出さない
    var onReissue: (() async -> Void)?
    @State private var notice: String?
    @State private var confirmReissue = false

    var body: some View {
        Section("招待") {
            if let image = QRCode.image(for: code.link?.absoluteString ?? code.text) {
                VStack(spacing: 6) {
                    // QR コードを長押しすると、画像の保存と、招待の作り直しのメニューが出る(普段は使わない機能)
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("招待の QR コード")
                        .contextMenu {
                            Button {
                                UIImageWriteToSavedPhotosAlbum(QRCode.padded(image), nil, nil, nil)
                                show("QR コードを写真に保存しました")
                            } label: { Label("画像を保存", systemImage: "arrow.down.circle") }
                            if onReissue != nil {
                                Button(role: .destructive) { confirmReissue = true } label: {
                                    Label("招待を作り直す", systemImage: "arrow.triangle.2.circlepath")
                                }
                            }
                        }
                    if let notice {
                        Text(notice).font(.app(12)).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
                .confirmationDialog("招待を作り直しますか?", isPresented: $confirmReissue, titleVisibility: .visible) {
                    Button("作り直す", role: .destructive) {
                        Task {
                            await onReissue?()
                            show("新しい招待に変わりました")
                        }
                    }
                } message: {
                    Text("いまの QR コードと招待リンクは使えなくなります。すでに参加している人は、そのままです。")
                }
            }
            if let link = code.link {
                ShareLink(item: link, message: Text("シフトパレットの共有カレンダー「\(calendarName)」に招待されました。")) {
                    Label("招待リンクを送る", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func show(_ text: String) {
        notice = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if notice == text { notice = nil }
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
