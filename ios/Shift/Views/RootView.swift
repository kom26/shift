import SwiftUI
import UIKit

enum CalendarMode: String { case week, month }

struct EditorTarget: Identifiable {
    let event: ShiftEvent
    let isNew: Bool
    var favorite = false
    var id: String { event.id }
}

/// 予定一覧の上に重ねて開く画面(自分の予定の編集、共有カレンダーの予定の編集、共有カレンダーの予定の詳細)
enum DayEditTarget: Identifiable {
    case own(EditorTarget)
    case shared(SharedEditTarget)
    case detail(SharedDetailTarget)

    var id: String {
        switch self {
        case .own(let t): return t.id
        case .shared(let t): return t.id.uuidString
        case .detail(let t): return t.id.uuidString
        }
    }
}

struct PaydayTarget: Identifiable {
    let date: String
    var id: String { date }
}

struct DayTarget: Identifiable {
    let date: String
    var id: String { date }
}

/// 予定をドラッグして日付で離したときの、移動・コピーの選択
struct DropChoice: Identifiable {
    let id = UUID()
    let eventId: String
    let date: String
    let title: String
    /// 移動先のセルの枠(画面全体の座標)
    var rect: CGRect = .zero
    var color = "#bec1cc"
    var label = ""
}

struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(Holidays.self) private var holidays
    @Environment(AuthService.self) private var auth
    @Environment(CalendarService.self) private var calendarService
    @Environment(SharedViewState.self) private var sharedView
    @Environment(SharedPublisher.self) private var publisher
    @AppStorage("mode") private var mode: CalendarMode = .month
    @AppStorage("startMonday") private var startMonday = false
    @AppStorage(CalendarBackground.personalKey) private var calendarBackgroundKey = ""
    @AppStorage("summaryOn") private var summaryOn = false
    @AppStorage("unplacedCollapsed") private var unplacedCollapsed = false

    @State private var anchor = Rules.today()
    @State private var editing: EditorTarget?
    @State private var showSettings = false
    @State private var showFilter = false
    @State private var showDrawer = false
    @State private var showLabels = false
    @State private var showWorkplaces = false
    /// 開始・締切・タスクの管理画面と、追加・編集の画面
    @State private var showTasks = false
    @State private var taskEditing: TaskEditTarget?
    /// 予定をドラッグして日付で離したときの「移動 / コピー」の選択
    @State private var dropChoice: DropChoice?
    /// 招待リンクから開いたが、アカウント登録がまだのとき、案内を出す
    @State private var showJoinNeedsAccount = false
    /// 右上の ⊕ を押して開く「予定追加 / 画像から追加」の 2 択(開いている間、ボタンは ⊗)
    @State private var addMenuOpen = false
    @State private var showShotImport = false
    @State private var showCreateCalendar = false
    /// 参加の確認。招待コードを持たせて開く(コードが空のまま開かないように)
    @State private var joinTarget: JoinTarget?
    @State private var sharedEditing: SharedEditTarget?
    @State private var sharedDetail: SharedDetailTarget?
    /// アカウント登録の前に開いた招待。端末に残しておき、登録が済んだら上から順に参加の確認を開く
    @AppStorage("pending-invites") private var pendingInvitesJSON = ""
    private var pendingInvites: [PendingInvite] {
        get { PendingInvite.decode(pendingInvitesJSON) }
        nonmutating set { pendingInvitesJSON = PendingInvite.encode(newValue) }
    }
    /// 登録をうながす案内を出している招待
    @State private var alertInvite: PendingInvite?
    /// 参加の確認を開く準備中(続けて 2 つ開かないための印)
    @State private var joinPresenting = false
    @State private var calendarDetail: SharedCalendar?
    /// 手動共有の確認を開いている共有カレンダー
    @State private var reviewCalendar: SharedCalendar?
    @State private var paydayTarget: PaydayTarget?
    @State private var dayTarget: DayTarget?
    @State private var pagerCommand: PagerCommand?
    @State private var selectedDate: String?
    @State private var selectTodayAfterMove = false
    /// スタンプモード中のよく使う予定のID
    @State private var stampId: String?
    /// アラームのスタンプモード(時間を合わせて「セット」を押した状態)
    @State private var alarmStamp: AlarmPreset?
    @State private var toast: String?
    /// 日付なし予定の作成を始めたときの未配置の数。保存で増えたら未配置ページを開く
    @State private var unplacedCountOnCreate: Int?
    /// 共有カレンダーを開いたまま、共有に出した自分の予定を直している(保存したあとも、その共有カレンダーに残る)
    @State private var ownEditFromShared = false
    @State private var revealToken = 0
    @Environment(\.scenePhase) private var scenePhase

    /// カレンダーの背景(ヘッダーも含む)。共有カレンダーを開いている間は、その共有カレンダーの背景
    private var calendarBackgroundColor: Color {
        CalendarBackground.color(sharedView.isOpen ? sharedView.background : calendarBackgroundKey)
    }

    var body: some View {
        mainBody
            // 開いた共有カレンダーで、まだ見ていない退会のお知らせがあれば出す
            .onChange(of: sharedView.calendar?.id) { _, id in showNotices(for: id) }
            .environment(\.eventSaved, eventSaved)
            .sheet(item: $taskEditing) { TaskEditor(original: $0.task, isNew: $0.isNew) }
            .sheet(isPresented: $showTasks) { TaskManageView() }
            // カレンダーを切り替えたり、ドロワーを開いたり、週表示にしたりしたら、その日の予定一覧は閉じる
            // (長い式で型の検査が終わらなくなるので、mainBody の外に置く)
            .onChange(of: sharedView.calendar?.id) { _, _ in dayTarget = nil }
            .onChange(of: showDrawer) { _, open in if open { dayTarget = nil } }
            .onChange(of: mode) { _, new in if new == .week { dayTarget = nil } }
    }

    private func showNotices(for id: String?) {
        guard let id else { return }
        Task {
            let lines = await calendarService.takeNotices(for: id)
            if !lines.isEmpty { showToast(lines.joined(separator: "\n")) }
        }
    }

    // 式が長くなりすぎて型が決まらなくなるので、本体を分けてある
    private var mainBody: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if sharedView.isOpen { sharedBanner }
            if sharedView.isOpen, let cal = sharedView.calendar.flatMap({ latestCalendar($0) }),
               cal.myShareManual, publisher.pendingCount(for: cal.id) > 0 {
                sharedPendingStrip(cal)
            }
            GeometryReader { geo in
                VStack(spacing: 0) {
                    if !unplacedCollapsed {
                        // 未配置エリアの高さは月(5週)基準で固定。6週の月でも週表示でも変えない
                        pager.frame(height: LayoutMath.monthCalendarHeight(available: geo.size.height, weeks: 5))
                    } else {
                        pager
                    }
                    // 共有カレンダーでも、下に未配置エリアを出す(中身は、共有カレンダーの未配置の予定だけ)
                    UnplacedArea(anchor: anchor, selectedDate: selectedDate, startMonday: startMonday,
                                 fillHeight: true, revealUnplaced: revealToken, stampId: $stampId, alarmStamp: $alarmStamp, onSelectEvent: edit, onUnplacedOwn: { sharedView.close(); revealToken += 1 },
                                 onEditFavorite: { editing = EditorTarget(event: $0, isNew: false, favorite: true) },
                                 onNewFavorite: { editing = EditorTarget(event: .newUnplaced(), isNew: true, favorite: true) })
                        .environment(displayStore)
                }
            }
        }
        .task(id: Rules.ymd(anchor).year) { await holidays.load(around: Rules.ymd(anchor).year) }
        .task { await AlarmService.shared.refresh(store: store) }
        .onChange(of: scenePhase) { _, new in
            if new == .active { Task { await AlarmService.shared.refresh(store: store) } }
        }
        .background(calendarBackgroundColor.ignoresSafeArea())
        .environment(\.calendarBackground, calendarBackgroundColor)
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.app(13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.8), in: Capsule())
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if showDrawer { drawer }
            if addMenuOpen { addMenu }
            if let c = dropChoice { dropChoiceMenu(c) }
        }
        .onChange(of: dropChoice?.id) { _, _ in
            DragState.shared.pendingId = dropChoice?.eventId
            DragState.shared.pendingDate = dropChoice?.date
        }
        .onChange(of: anchor) { _, _ in
            // 「今日」ボタンで動いたときだけ、今日を選んだ状態にする
            selectedDate = selectTodayAfterMove ? Rules.today() : nil
            selectTodayAfterMove = false
        }
        .onChange(of: stampId) { _, new in
            // スタンプで置いた予定が、絞り込みで隠れて消えたように見えないよう、スタンプを始めるときは全部表示にする
            if new != nil { store.clearFilters() }
        }
        .onChange(of: alarmStamp) { _, new in
            if new != nil { store.clearFilters() }
        }
        .onChange(of: mode) { _, new in
            // 日付を選んだまま週表示にしたら、その日を含む週を出す
            if new == .week, let d = selectedDate { anchor = d }
            selectedDate = nil
        }
        .onChange(of: auth.account?.uid) { _, _ in presentPendingJoin() }
        .onAppear {
            // 承認待ちだった共有カレンダーが承認されたら、すぐ見られることを知らせる
            calendarService.onApproved = { cal in showToast("「" + cal.name + "」に参加できました") }
            calendarService.onGone = { g in showToast(g.text) }
            presentPendingJoin()
            fillInviteNames()
        }
        .onOpenURL { url in
            // 招待リンクから: shiftpalette://join/<招待コード> で、参加の確認を開く(ログイン前なら設定へ)
            // https://shift-palette.web.app/join/<招待コード> (QR やリンク。Universal Links)でも同じ
            let isJoin = (url.scheme == "shiftpalette" && url.host == "join")
                || (url.scheme == "https" && url.host == "shift-palette.web.app" && url.pathComponents.dropFirst().first == "join")
            if isJoin, let code = url.pathComponents.last, code != "/", code != "join" {
                // 起動直後はログインの復元が終わっていないので、コードを覚えておき、確認できたら参加画面を開く
                stockInvite(code)
                presentPendingJoin()
                if auth.account == nil {
                    // しばらく待ってもログインしていなければ、アカウント登録をうながす
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if auth.account == nil, let inv = pendingInvites.first(where: { $0.code == code }) {
                            alertInvite = inv
                            showJoinNeedsAccount = true
                        }
                    }
                }
                return
            }
            // ウィジェットから: shiftpalette://day/2026-10-30 でその日の予定一覧を開く
            guard url.scheme == "shiftpalette", url.host == "day",
                  let date = url.pathComponents.last, Rules.parse(date) != nil else { return }
            // ウィジェットで見ていたカレンダー(自分か、共有か)で、その日を選んだ状態にして、その日の予定一覧を開く
            let shared = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "cal" }?.value
            Task { await openDayFromWidget(date, sharedId: shared) }
        }
        .sheet(item: $editing, onDismiss: {
            if let n = unplacedCountOnCreate, store.unplacedEvents.count > n { revealToken += 1 }
            unplacedCountOnCreate = nil
        }) { ownEditor($0) }
        .sheet(item: $paydayTarget) { PaydaySheet(date: $0.date) }
        .sheet(item: $dayTarget) { t in
            DaySheet(date: t.date, canAdd: !sharedView.isOpen || sharedView.canCreate, onSelectPayday: { date in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { paydayTarget = PaydayTarget(date: date) }
            }, makeAddTarget: dayAddTarget, makeEditTarget: dayEditTarget, addEditor: { AnyView(dayAddEditor($0)) })
            .environment(displayStore)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .alert(inviteAlertTitle, isPresented: $showJoinNeedsAccount) {
            Button("アカウント登録") { showSettings = true }
            Button("あとで", role: .cancel) {}
        } message: {
            Text(inviteAlertMessage)
        }
        .sheet(isPresented: $showFilter) { FilterSheet() }
        .sheet(isPresented: $showLabels) { LabelManageView() }
        .sheet(isPresented: $showWorkplaces) { WorkplaceManageView() }
        .sheet(item: $sharedEditing) { sharedEditor($0) }
        .sheet(item: $sharedDetail) { SharedEventDetail(eventId: $0.eventId) }
        .sheet(isPresented: $showCreateCalendar) { CalendarCreateSheet() }
        .sheet(item: $joinTarget, onDismiss: {
            joinPresenting = false
            // ほかに待っている招待があれば、続けて開く
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { presentPendingJoin() }
        }) { CalendarJoinSheet(code: $0.code) }
        .sheet(item: $calendarDetail) { CalendarDetailSheet(calendar: $0) }
        .sheet(item: $reviewCalendar) { ShareReviewSheet(calendar: $0) }
    }

    private var inviteAlertName: String {
        pendingInvites.first { $0.code == alertInvite?.code }?.name ?? ""
    }

    private var inviteAlertTitle: String {
        let name = inviteAlertName
        return name.isEmpty ? "共有カレンダーに招待されました" : "「\(name)」に招待されました"
    }

    private var inviteAlertMessage: String {
        let name = inviteAlertName
        let target = name.isEmpty ? "共有カレンダー" : "共有カレンダー「\(name)」"
        return "\(target)に参加するにはアカウント登録かログインが必要です。"
    }

    /// 開いた招待を、順番待ちに入れる(同じ共有カレンダーの招待は、新しい方に置き換える)
    private func stockInvite(_ code: String) {
        var list = pendingInvites
        let cid = InviteCode.parse(code)?.calendarId
        list.removeAll { $0.code == code || (cid != nil && InviteCode.parse($0.code)?.calendarId == cid) }
        list.append(PendingInvite(code: code, name: ""))
        pendingInvites = list
        fillInviteNames()
    }

    /// 名前がまだ分からない招待の名前を調べる
    private func fillInviteNames() {
        for inv in pendingInvites where inv.name.isEmpty {
            Task {
                guard let n = await calendarService.inviteName(code: inv.code) else { return }
                var list = pendingInvites
                if let i = list.firstIndex(where: { $0.code == inv.code }) {
                    list[i].name = n
                    pendingInvites = list
                }
            }
        }
    }

    /// 待っている招待があり、ログインしていれば、先頭から参加画面を開く(ほかのシートが開いていれば閉じてから)
    private func openDayFromWidget(_ date: String, sharedId: String?) async {
        // アプリが閉じていたときは、共有カレンダーの一覧がまだ読めていない。読めるまで少し待つ(待たないと、自分のカレンダーが開いてしまう)
        if let id = sharedId {
            var waited = 0
            while waited < 20, !calendarService.calendars.contains(where: { $0.id == id && $0.status == .active }) {
                try? await Task.sleep(for: .milliseconds(200))
                waited += 1
            }
        }
        if let id = sharedId, let c = calendarService.calendars.first(where: { $0.id == id && $0.status == .active }) {
            if sharedView.calendar?.id != id { await sharedView.open(c) }
        } else {
            sharedView.close()
        }
        selectTodayAfterMove = false
        // ウィジェットからは、いつも月表示で開く(週表示で見ていても)
        mode = .month
        anchor = date
        // 日付が動いたときの「選択を外す」処理のあとに、その日を選ぶ
        try? await Task.sleep(for: .milliseconds(150))
        selectedDate = date
        dayTarget = DayTarget(date: date)
    }

    private func presentPendingJoin() {
        guard auth.account != nil, joinTarget == nil, !joinPresenting, let next = pendingInvites.first else { return }
        pendingInvites = Array(pendingInvites.dropFirst())
        joinPresenting = true
        let open = {
            joinTarget = JoinTarget(code: next.code)
        }
        if showSettings || showDrawer {
            showSettings = false
            withAnimation(.snappy) { showDrawer = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: open)
        } else {
            open()
        }
    }

    private func closeDrawer(then action: (() -> Void)? = nil) {
        withAnimation(.snappy) { showDrawer = false }
        if let action { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: action) }
    }

    /// 左上のメニューから開く。カレンダーの切り替えと、レイヤー・設定への入り口
    private var drawer: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.3).ignoresSafeArea()
                .onTapGesture { closeDrawer() }
            VStack(alignment: .leading, spacing: 4) {
                Text("カレンダー")
                    .font(.app(12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                drawerRow(title: "自分のカレンダー", icon: "calendar", selected: !sharedView.isOpen) {
                    sharedView.close()
                    closeDrawer()
                }
                if auth.account != nil {
                    // 「共有カレンダー」の見出しの下に、中身を 1 文字ぶん右へずらして並べる
                    HStack(spacing: 12) {
                        Image(systemName: "person.2.fill").frame(width: 24)
                        Text("共有カレンダー").font(.app(16, weight: .semibold))
                        Spacer()
                        // 右の ⊕ で、共有カレンダーを作る画面を開く(参加は、招待の QR・リンクから)
                        Button { closeDrawer { showCreateCalendar = true } } label: {
                            Image(systemName: "plus.circle")
                                .font(.app(20))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 40, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("共有カレンダーを作る")
                    }
                    .foregroundStyle(Color.secondary)
                    .padding(.leading, 12)
                    .frame(minHeight: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(calendarService.calendars) { cal in
                            calendarRow(cal)
                        }
                    }
                    .padding(.leading, 16)
                } else {
                    // 登録の前に開いた招待は、参加待ちとして並べる(押すと、登録をうながす案内をもう一度出す)
                    ForEach(pendingInvites) { inv in
                        drawerRow(title: inv.name.isEmpty ? "共有カレンダー" : inv.name, icon: "person.2", caption: "参加待ち(アカウント登録が必要)") {
                            closeDrawer {
                                alertInvite = inv
                                showJoinNeedsAccount = true
                            }
                        }
                    }
                    drawerRow(title: "アカウント登録かログインして共有カレンダーを使う", icon: "person.crop.circle.badge.plus") {
                        closeDrawer { showSettings = true }
                    }
                }
                Divider().padding(.vertical, 8)
                drawerRow(title: "職場の管理", icon: "briefcase") { closeDrawer { showWorkplaces = true } }
                drawerRow(title: "ラベルの管理", icon: "tag") { closeDrawer { showLabels = true } }
                drawerRow(title: "タスク・開始・締切管理", icon: "checklist") { closeDrawer { showTasks = true } }
                drawerRow(title: "設定", icon: "gearshape") { closeDrawer { showSettings = true } }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(width: 280)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color(.systemBackground).ignoresSafeArea())
            .shadow(color: .black.opacity(0.2), radius: 10, x: 4)
            .gesture(DragGesture().onEnded { if $0.translation.width < -40 { closeDrawer() } })
            .transition(.move(edge: .leading))
        }
    }

    /// 共有カレンダーの行。タップで開く(承認待ちなら案内)。右の ⓘ で、招待・参加者・自分の設定
    private func calendarRow(_ cal: SharedCalendar) -> some View {
        HStack(spacing: 0) {
            drawerRow(title: cal.name, icon: cal.icon, caption: cal.status == .pending ? "承認待ち" : nil,
                      selected: sharedView.calendar?.id == cal.id) {
                if cal.status == .active {
                    closeDrawer { Task { await sharedView.open(cal) } }
                } else {
                    closeDrawer { calendarDetail = cal }
                }
            }
            // 手動共有で、まだ共有していない変更の数
            if cal.myShareManual, publisher.pendingCount(for: cal.id) > 0 {
                Text("\(publisher.pendingCount(for: cal.id))")
                    .font(.app(12, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Color.red, in: Capsule())
            }
        }
    }

    /// 共有カレンダーの、いまの状態(設定を変えたあとも新しい内容で見る)
    private func latestCalendar(_ cal: SharedCalendar) -> SharedCalendar {
        calendarService.calendars.first { $0.id == cal.id } ?? cal
    }

    /// 手動共有で、まだ共有していない変更があるときだけ出る帯。タップで確認の画面へ
    private func sharedPendingStrip(_ cal: SharedCalendar) -> some View {
        let n = publisher.pendingCount(for: cal.id)
        return Button { reviewCalendar = cal } label: {
            HStack(spacing: 8) {
                Text("\(n)")
                    .font(.app(12, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(Theme.alarm, in: Capsule())
                Text("\(n)件の変更がまだ共有されていません")
                    .font(.app(13, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("確認して共有")
                    .font(.app(12, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.accent, in: Capsule())
            }
            .foregroundStyle(Theme.payText)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.payFill)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(n)件の変更がまだ共有されていません。確認して共有する")
    }

    /// 共有カレンダーを開いている間の帯。ほかの人の予定は見るだけで、自分の予定には触れないことを示す
    private var sharedBanner: some View {
        HStack(spacing: 8) {
            CalendarIconView(icon: sharedView.calendar?.icon ?? CalendarIcon.defaultName, size: 20)
            Text("\(sharedView.calendar?.name ?? "")" + (sharedView.canCreate ? "" : " (見るだけ)"))
                .font(.app(13, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            if sharedView.loading { ProgressView().controlSize(.small) }
            if sharedView.failed { Text("読み込めませんでした").font(.app(11)) }
            Button { sharedView.close() } label: {
                Text("自分のカレンダーに戻る")
                    .font(.app(12, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.25), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Theme.onAccent)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 34)
        .background(Theme.accent)
    }

    private func drawerRow(title: String, icon: String, caption: String? = nil, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CalendarIconView(icon: icon, size: 24)
                // 状態(参加待ち・承認待ち)は、名前の下の小さな文字で出す。名前が長くても、切れない
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.app(16, weight: selected ? .semibold : .regular)).lineLimit(2)
                    if let caption { Text(caption).font(.app(11)).foregroundStyle(.secondary) }
                }
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
            }
            .foregroundStyle(selected ? Theme.accent : Color.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(selected ? Theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        VStack(spacing: 8) {
            if stampFavorite != nil || alarmStamp != nil {
                stampBanner
            } else {
                HStack(spacing: 8) {
                    Button { withAnimation(.snappy) { showDrawer = true } } label: {
                        Image(systemName: "line.3.horizontal").font(.title3)
                            .padding(.horizontal, 6)
                            .frame(minHeight: 36)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("メニュー")
                    Spacer(minLength: 0)
                    Button { pagerCommand = PagerCommand(direction: -1, id: UUID()) } label: { Image(systemName: "chevron.left") }
                    Text(title).font(.app(17, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    Button { pagerCommand = PagerCommand(direction: 1, id: UUID()) } label: { Image(systemName: "chevron.right") }
                    Spacer(minLength: 0)
                    // 丸い ⊕。押すと「予定追加 / 画像から追加」が開き、ボタンは ⊗ に変わる(もう一度押すと閉じて、⊕ に戻る)。
                    // 共有カレンダーを開いているときは、2 択を出さず、共有カレンダーに予定を追加する
                    Button { tapAdd() } label: {
                        // 「＋」を 45 度まわして「×」に見せる(戻すときは逆にまわる)
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                            .rotationEffect(.degrees(addMenuOpen ? 45 : 0))
                            .frame(width: 36, height: 36)
                            .background(Theme.accent, in: Circle())
                    }
                    .accessibilityLabel(addMenuOpen ? "閉じる" : (sharedView.isOpen ? "共有カレンダーに予定を追加" : addButtonTitle))
                    .disabled(sharedView.isOpen && !sharedView.canCreate)
                    .opacity(sharedView.isOpen && !sharedView.canCreate ? 0.5 : 1)
                    .sheet(isPresented: $showShotImport) {
                        ScreenshotImportSheet(onAdded: { showToast("\($0)件の予定を追加しました") })
                    }
                }
            }
            HStack(spacing: 10) {
                TwoWayPicker("表示", selection: $mode.animation(.snappy), first: ("週", CalendarMode.week), second: ("月", CalendarMode.month))
                .frame(width: 110)
                Button { goToday() } label: {
                    Text("今日").font(.app(15)).padding(.horizontal, 6).frame(minHeight: 36).contentShape(Rectangle())
                }
                Spacer(minLength: 0)
                if sharedView.isOpen {
                    // 共有カレンダーでは、週計の代わりに、その共有カレンダーの設定(インフォ)を開く
                    Button { calendarDetail = sharedView.calendar } label: {
                        Image(systemName: "gearshape")
                            .font(.app(20))
                            .foregroundStyle(Color.primary)
                            .frame(minWidth: 36, minHeight: 36)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("共有カレンダーの設定")
                } else {
                Button { toggleSummary() } label: {
                    Text("週計")
                        .font(.app(12, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(summaryOn ? Theme.accentSoft : Color.clear, in: Capsule())
                        .overlay(Capsule().stroke(summaryOn ? Theme.accent : Color.secondary.opacity(0.4)))
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                }
                }
                if !sharedView.isOpen {
                Button { showFilter = true } label: {
                    Image(systemName: store.isFiltering || sharedView.isOverlaying
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                        .font(.app(20))
                        .foregroundStyle(store.isFiltering || sharedView.isOverlaying ? Theme.accent : Color.primary)
                        .frame(minWidth: 36, minHeight: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("職場フィルタ")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var stampFavorite: ShiftEvent? {
        stampId.flatMap { store.favorite(id: $0) }
    }

    /// スタンプモード中、ヘッダー1行目(設定・年月・予定追加)の代わりに出す帯
    @ViewBuilder
    private var stampBanner: some View {
        if stampFavorite != nil || alarmStamp != nil {
            HStack(spacing: 8) {
                Text(stampBannerText)
                    .font(.app(12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Button { withAnimation(.snappy) { stampId = nil; alarmStamp = nil } } label: {
                    Text("完了")
                        .font(.app(12, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.25), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var title: String {
        if mode == .month {
            let p = Rules.ymd(anchor)
            return "\(p.year)年\(p.month)月"
        }
        let s = Rules.weekStart(of: anchor, startMonday: startMonday)
        let sp = Rules.ymd(s), ep = Rules.ymd(Rules.addDays(s, 6))
        return sp.month == ep.month
            ? "\(sp.year)年\(sp.month)月\(sp.day)〜\(ep.day)日"
            : "\(sp.month)月\(sp.day)日〜\(ep.month)月\(ep.day)日"
    }

    private var pager: some View {
        PagerView(prev: page(offset: -1), current: page(offset: 0), next: page(offset: 1),
                  command: $pagerCommand,
                  onCommit: { dir in
                      anchor = mode == .month ? Rules.addMonths(anchor, dir) : Rules.addDays(anchor, 7 * dir)
                  })
            .id(mode)
            .transition(.opacity)
            .environment(\.isStamping, stampId != nil || alarmStamp != nil)
            .environment(displayStore)
            .environment(\.isSharedView, sharedView.isOpen)
    }

    /// カレンダー部品が読む予定の入れ物。共有カレンダーを開いている間は、参加者の予定を入れた表示用のもの(自分のデータには触れない)
    private var displayStore: Store { sharedView.store ?? store }

    @ViewBuilder
    private func page(offset k: Int) -> some View {
        switch mode {
        case .month:
            MonthView(anchor: Rules.addMonths(anchor, k), startMonday: startMonday, summaryOn: summaryOn && !sharedView.isOpen, selectedDate: selectedDate, onSelectDay: tapDay, onSelectEvent: edit, onTapEvent: tapEvent, onDropEvent: drop, onSelectPayday: { paydayTarget = PaydayTarget(date: $0) }, onLongPressDay: longPressDay)
        case .week:
            WeekView(anchor: Rules.addDays(anchor, 7 * k), startMonday: startMonday, summaryOn: summaryOn, selectedDate: selectedDate, onSelectDay: tapDay, onSelectEvent: edit, onTapEvent: tapEvent, onDropEvent: drop, onSelectPayday: { paydayTarget = PaydayTarget(date: $0) }, onLongPressDay: longPressDay)
        }
    }

    /// 今日を含むページへ移り、今日を選択した状態にする
    private func goToday() {
        let today = Rules.today()
        if anchor == today {
            selectedDate = today
        } else {
            selectTodayAfterMove = true
            withAnimation(.snappy) { anchor = today }
        }
    }

    /// 週計を切り替えると未配置エリアを必ず折りたたむ(自動では開かない)
    private func toggleSummary() {
        withAnimation(.snappy) {
            summaryOn.toggle()
        }
    }

    private var stampBannerText: String {
        if let fav = stampFavorite {
            let time = Rules.timeLabel(fav)
            return "「\(fav.title)\(time.isEmpty ? "" : " " + time)」を置く日をタップ"
        }
        if let spec = alarmStamp { return "⏰ \(spec.label) をセットする日をタップ" }
        return ""
    }

    private func showToast(_ text: String) {
        withAnimation(.snappy) { toast = text }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.snappy) { if toast == text { toast = nil } }
        }
    }

    /// アラームのスタンプ: 日付のタップでセット、同じ日にもう一度タップで解除
    private func toggleAlarm(_ spec: AlarmPreset, on date: String) {
        Task { @MainActor in
            let r = await AlarmService.shared.toggle(spec: spec, on: date, store: store)
            switch r {
            case .set: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case .removed: UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case .noShift:
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                showToast("この日には時刻のあるシフトがありません")
            case .past:
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                showToast("鳴る時刻を過ぎています")
            case .denied:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                showToast("設定アプリでアラームを許可してください")
            case .unsupported:
                showToast("アラームは iOS 26 以降で使えます")
            case .failed:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                showToast("アラームをセットできませんでした")
            }
        }
    }

    private var addButtonTitle: String {
        guard let d = selectedDate else { return "予定追加" }
        let p = Rules.ymd(d)
        return "\(p.month)月\(p.day)日に予定追加"
    }

    /// 右上の ⊕ を押したとき。共有カレンダーを開いているときは、そのまま追加。そうでなければ 2 択を開閉する
    private func tapAdd() {
        if sharedView.isOpen {
            addFromHeader()
        } else {
            withAnimation(.snappy) { addMenuOpen.toggle() }
        }
    }

    private func closeAddMenu() {
        withAnimation(.snappy) { addMenuOpen = false }
    }

    /// 右上の ⊕ の下に出る 2 択
    private var addMenu: some View {
        ZStack(alignment: .topTrailing) {
            // うしろを暗くして、メニューが開いているのが分かるようにする
            Color.black.opacity(0.38).ignoresSafeArea().onTapGesture { closeAddMenu() }
            // 暗くしたうえに、右上のボタン(×になったもの)だけ、明るいまま重ねる
            Button { closeAddMenu() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .rotationEffect(.degrees(45))
                    .frame(width: 36, height: 36)
                    .background(Theme.accent, in: Circle())
            }
            .accessibilityLabel("閉じる")
            .padding(.top, 8)
            .padding(.trailing, 12)
            VStack(alignment: .leading, spacing: 0) {
                addMenuRow(icon: "calendar.badge.plus", title: addButtonTitle) {
                    closeAddMenu()
                    addFromHeader()
                }
                Divider()
                addMenuRow(icon: "photo.on.rectangle", title: "画像から追加") {
                    closeAddMenu()
                    // 読み取りは、サーバー経由で使うので、ログインが要る
                    if auth.account == nil {
                        showToast("画像から追加は、アカウント登録かログインが必要です")
                    } else {
                        showShotImport = true
                    }
                }
                Divider()
                addMenuRow(icon: "flag", title: "開始・締切予定追加") {
                    closeAddMenu()
                    let d = selectedDate ?? Rules.today()
                    taskEditing = TaskEditTarget(task: .new(dueDate: d), isNew: true)
                }
            }
            .frame(width: 230)
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
            .padding(.top, 48)
            .padding(.trailing, 12)
            .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
        }
    }

    private func addMenuRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 24).foregroundStyle(Theme.accent)
                Text(title).font(.app(15)).foregroundStyle(Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 日付セルのタップ: スタンプ中は配置、そうでなければ選択。選択中の日をもう一度タップで一覧
    private func tapDay(_ date: String) {
        if alarmStamp != nil || stampId != nil {
            addEvent(on: date)
        } else if selectedDate == date {
            dayTarget = DayTarget(date: date)
        } else {
            selectedDate = date
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    /// 予定バーのタップ: 最初のタップは、バーに触れていても日付セルの選択。その日が選択済みなら編集
    private func tapEvent(_ event: ShiftEvent, on date: String) {
        if alarmStamp == nil, stampId == nil, selectedDate == date {
            edit(event)
        } else {
            tapDay(date)
        }
    }

    /// 日付セルの長押し: その日の予定を追加(スタンプ中は何もしない)
    private func longPressDay(_ date: String) {
        guard alarmStamp == nil, stampId == nil else { return }
        createEvent(on: date)
    }

    private func createEvent(on date: String) {
        if sharedView.isOpen {
            // 共有カレンダーの中に予定を作る(参加者全員が直せる)
            if let e = sharedView.newEvent(on: date) {
                selectedDate = date
                sharedEditing = SharedEditTarget(event: e, isNew: true)
            }
            return
        }
        selectedDate = date
        editing = EditorTarget(event: .new(on: date), isNew: true)
    }

    /// 予定一覧の＋から開く編集画面。一覧は閉じずに、その上に重ねて開く
    private func dayAddTarget(_ date: String) -> DayEditTarget? {
        selectedDate = date
        if sharedView.isOpen {
            guard let e = sharedView.newEvent(on: date) else { return nil }
            return .shared(SharedEditTarget(event: e, isNew: true))
        }
        return .own(EditorTarget(event: .new(on: date), isNew: true))
    }

    /// 予定一覧で予定を押したとき。一覧は閉じずに、その上に重ねて開く(edit と同じ分け方)
    private func dayEditTarget(_ event: ShiftEvent) -> DayEditTarget? {
        ownEditFromShared = false
        if sharedView.isOpen, let own = sharedView.ownEvent(for: event.id) {
            ownEditFromShared = true
            return .own(EditorTarget(event: own, isNew: false))
        }
        if sharedView.event(event.id) != nil { return .detail(SharedDetailTarget(eventId: event.id)) }
        if sharedView.isOpen { return nil }
        return .own(EditorTarget(event: event, isNew: false))
    }

    @ViewBuilder
    private func dayAddEditor(_ target: DayEditTarget) -> some View {
        switch target {
        case .own(let t):
            // 一覧には表示用のストアが入っているので、編集画面には本物のストアを渡す
            ownEditor(t).environment(store)
        case .shared(let t):
            sharedEditor(t)
        case .detail(let t):
            SharedEventDetail(eventId: t.eventId)
        }
    }

    /// 自分の予定の編集(よく使う予定は、保存先を切り替えない)
    @ViewBuilder
    private func ownEditor(_ t: EditorTarget) -> some View {
        if t.favorite {
            EventEditor(original: t.event, isNew: t.isNew, favoriteMode: true)
        } else {
            EventEditorFlow(ownEvent: t.event, isNew: t.isNew)
        }
    }

    private func sharedEditor(_ t: SharedEditTarget) -> some View {
        EventEditorFlow(sharedEvent: t.event, calendarId: sharedView.calendar?.id ?? "", isNew: t.isNew)
    }

    /// 予定を保存したあと。保存先のカレンダーで、その予定の月を開き、その日の予定一覧を開く
    private func eventSaved(date: String?, calendarId: String?) {
        // 共有に出した自分の予定を直したときは、いま開いている共有カレンダーのまま
        var calendarId = calendarId
        if ownEditFromShared, calendarId == nil, sharedView.isOpen { calendarId = sharedView.calendar?.id }
        ownEditFromShared = false
        guard let date else {
            // 日付を決めない予定は、未配置エリアに入る。保存先のカレンダーを開いて、下の未配置エリアを出す
            sharedDetail = nil
            dayTarget = nil
            let target = calendarId
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                Task {
                    await showCalendar(target)
                    revealToken += 1
                    showToast("日付未定のため未配置エリアに保存しました")
                }
            }
            return
        }
        // 予定一覧からの編集で、同じカレンダー・同じ日のままなら、一覧がそのまま残っている
        if dayTarget?.date == date, sharedView.calendar?.id == calendarId { return }
        sharedDetail = nil
        // 編集画面が閉じきってから開く
        let target = calendarId
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            Task { await openDayFromWidget(date, sharedId: target) }
        }
    }

    /// 自分のカレンダー(nil)か、その共有カレンダーを開く
    private func showCalendar(_ id: String?) async {
        if let id, let c = calendarService.calendars.first(where: { $0.id == id && $0.status == .active }) {
            if sharedView.calendar?.id != id { await sharedView.open(c) }
        } else {
            sharedView.close()
        }
    }

    private func addFromHeader() {
        if let d = selectedDate { createEvent(on: d) } else if sharedView.isOpen { addSharedUnplaced() } else { addUnplaced() }
    }

    /// 共有カレンダーの中に、日付を決めない予定(未配置)を作る。あとで、日にドラッグして置く
    private func addSharedUnplaced() {
        if let e = sharedView.newUnplacedEvent() { sharedEditing = SharedEditTarget(event: e, isNew: true) }
    }

    private func addEvent(on date: String) {
        if let spec = alarmStamp {
            toggleAlarm(spec, on: date)
            return
        }
        if let id = stampId {
            // スタンプモード: 日付のタップで配置、同じ日にもう一度タップで削除
            if let r = store.stampToggle(favoriteId: id, on: date) {
                UIImpactFeedbackGenerator(style: r == .placed ? .medium : .light).impactOccurred()
            } else {
                stampId = nil
            }
            return
        }
        selectedDate = date
        editing = EditorTarget(event: .new(on: date), isNew: true)
    }

    private func addUnplaced() {
        guard !sharedView.isOpen else { return }
        unplacedCountOnCreate = store.unplacedEvents.count
        editing = EditorTarget(event: .newUnplaced(), isNew: true)
    }

    private func edit(_ event: ShiftEvent) {
        // 開始・締切の印は、その項目の編集を開く
        if let m = event.taskMarker {
            if let t = store.task(id: m.taskId) { taskEditing = TaskEditTarget(task: t, isNew: false) }
            return
        }
        ownEditFromShared = false
        // 共有に出した自分の予定は、共有カレンダーを開いたままでも、自分の予定として直せる
        if sharedView.isOpen, let own = sharedView.ownEvent(for: event.id) {
            ownEditFromShared = true
            editing = EditorTarget(event: own, isNew: false)
            return
        }
        // 共有カレンダーの予定は、ほかの人の予定は詳細を見せる(直せるのは共有カレンダーの中で作った予定だけ)
        if sharedView.event(event.id) != nil {
            sharedDetail = SharedDetailTarget(eventId: event.id)
            return
        }
        if sharedView.isOpen { return }
        editing = EditorTarget(event: event, isNew: false)
    }

    /// 予定をドラッグして日付で離した。移動するか、コピーするかを選んでもらう(よく使う予定は、いつもコピーして置く)
    private func drop(id: String, on date: String) {
        if sharedView.isOpen {
            // 共有カレンダーでは、共有カレンダーの中で作った予定と、共有に出した自分の予定を動かせる
            guard !id.hasPrefix(Store.favoritePrefix), sharedView.canDrag(id) else { return }
            // 未配置からは、選択を出さず、すぐ置く(共有に出した自分の予定は、いつも配置済み)
            if sharedView.event(id)?.placed == false {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { await sharedView.place(id: id, on: date) }
                return
            }
            // 元と同じ日に離したときは、何も出さずに取り消す
            if sharedView.event(id)?.startDate == date { return }
            dropChoice = DropChoice(eventId: id, date: date, title: sharedView.event(id)?.title ?? "",
                                     rect: DragState.shared.dropRect, color: sharedView.event(id)?.color ?? "#bec1cc",
                                     label: sharedView.event(id)?.title ?? "")
            return
        }
        guard !store.isOverlay(id) else { return }
        if id.hasPrefix(Store.favoritePrefix) {
            withAnimation(.snappy) { store.stampCopy(favoriteId: String(id.dropFirst(Store.favoritePrefix.count)), on: date) }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            return
        }
        guard let event = store.events.first(where: { $0.id == id }) else { return }
        // 未配置からは、選択を出さず、すぐ置く
        if !event.placed {
            withAnimation(.snappy) { store.place(id: id, on: date) }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            return
        }
        // 元と同じ日に離したときは、何も出さずに取り消す
        if event.startDate == date { return }
        dropChoice = DropChoice(eventId: id, date: date, title: event.title, rect: DragState.shared.dropRect,
                                 color: event.color, label: event.barShowsTime ? Rules.timeLabel(event) : event.title)
    }

    /// 予定を日付に離したときの「移動 / コピー」。離した場所に、小さく出す(外をタップすると閉じる)
    private func dropChoiceMenu(_ c: DropChoice) -> some View {
        GeometryReader { geo in
            let o = geo.frame(in: .global).origin
            let w: CGFloat = 148, h: CGFloat = 40
            // 移動先のセルの下に出す(下に入らなければ、セルの上に)
            let cell = c.rect.offsetBy(dx: -o.x, dy: -o.y)
            let x = min(max(cell.midX, w / 2 + 8), geo.size.width - w / 2 - 8)
            let below = cell.maxY + 6 + h / 2
            let y = below + h / 2 + 8 <= geo.size.height ? below : max(h / 2 + 8, cell.minY - 6 - h / 2)
            ZStack {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { dropChoice = nil; DragState.shared.pendingId = nil; DragState.shared.pendingDate = nil }
                HStack(spacing: 0) {
                    Button("移動") { applyDrop(copy: false) }
                        .frame(maxWidth: .infinity, minHeight: h)
                    Divider().frame(height: 20)
                    Button("コピー") { applyDrop(copy: true) }
                        .frame(maxWidth: .infinity, minHeight: h)
                }
                .font(.app(15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
                .frame(width: w, height: h)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
                .position(x: x, y: y)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
    }

    private func applyDrop(copy: Bool) {
        guard let c = dropChoice else { return }
        dropChoice = nil
        // 選んだ時点で、薄い表示をすぐ解く(次のタッチまで残らないように)
        DragState.shared.pendingId = nil
        DragState.shared.pendingDate = nil
        DragState.shared.ended()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if sharedView.isOpen {
            if sharedView.ownEventId(for: c.eventId) != nil {
                // 共有に出した自分の予定は、自分のカレンダーの予定として動かす(共有カレンダーへは、あとで反映される)
                if copy { sharedView.copyOwn(id: c.eventId, on: c.date) } else { sharedView.placeOwn(id: c.eventId, on: c.date) }
            } else {
                Task {
                    if copy { await sharedView.copy(id: c.eventId, on: c.date) } else { await sharedView.place(id: c.eventId, on: c.date) }
                }
            }
        } else if copy {
            withAnimation(.snappy) { store.copy(id: c.eventId, to: [c.date]) }
        } else {
            withAnimation(.snappy) { store.place(id: c.eventId, on: c.date) }
        }
    }
}
