import FirebaseCore
import GoogleSignIn
import SwiftUI

@main
struct ShiftApp: App {
    @State private var store: Store
    @State private var holidays = Holidays()
    @State private var sync: AccountSync
    @State private var auth: AuthService
    @State private var calendars: CalendarService
    @State private var sharedView: SharedViewState
    @State private var publisher: SharedPublisher
    @AppStorage("startMonday") private var startMonday = false
    /// アプリを入れた直後は、ライトモード(設定で、自動・ダークに変えられる)
    @AppStorage(Appearance.key) private var appearance = Appearance.light
    @State private var profile: ProfileSettings
    @State private var updater = UpdateChecker()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppFont.register()
        FirebaseApp.configure()
        let s = Store()
        s.seedDefaultLabelsIfNeeded()
        s.migrateTitleWorkplacesIfNeeded()
        let a = AccountSync(store: s, backing: FirestoreBacking())
        let cal = CalendarService(backing: FirestoreCalendarBacking())
        let eventsBacking = FirestoreSharedEvents()
        let pub = SharedPublisher(backing: eventsBacking, store: s,
                                  calendars: { [weak cal] in cal?.calendars ?? [] }, uid: { [weak cal] in cal?.myUid })
        let shared = SharedViewState(events: eventsBacking, calendars: cal)
        shared.anniversaryBacking = FirestoreSharedAnniversaries()
        shared.attach(store: s)
        cal.onChange = { [weak pub, weak shared] in
            pub?.schedule()
            shared?.syncOverlay()
        }
        s.onLocalChange = { [weak a, weak s, weak pub] in
            a?.localChanged()
            pub?.schedule()
            if let s {
                WidgetSync.publish(store: s)
                // 予定を直したら、「予定の○分前」のアラームの時刻も、すぐ合わせる
                Task { await AlarmService.shared.refresh(store: s) }
            }
        }
        let prof = ProfileSettings()
        a.onApplied = { [weak s] in
            guard let s else { return }
            WidgetSync.publish(store: s)
            Task { await AlarmService.shared.refresh(store: s) }
            // アカウントから戻した設定(名前・アバターを含む)を、画面にも反映する
            Task { @MainActor in prof.reload() }
        }
        // 端末の設定(表示・給料など)を変えたら、アカウントにも送る
        _ = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak a] _ in
            a?.localChanged()
        }
        _profile = State(initialValue: prof)
        _store = State(initialValue: s)
        _sync = State(initialValue: a)
        _auth = State(initialValue: AuthService())
        _calendars = State(initialValue: cal)
        _publisher = State(initialValue: pub)
        _sharedView = State(initialValue: shared)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.font, .app(17))
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .environment(store)
                .environment(holidays)
                .environment(auth)
                .environment(sync)
                .environment(calendars)
                .environment(sharedView)
                .environment(publisher)
                .environment(profile)
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
                .tint(Theme.accent)
                .preferredColorScheme(appearance.colorScheme)
                .overlay { UpdateNoticeOverlay(checker: updater) }
                .task { await updater.check() }
                .overlay {
                    if sync.status.restoring || sync.status.choice != nil { RestoringOverlay(sync: sync) }
                }
                // ログインしている間だけ同期する。ログアウトや別のアカウントへの切り替えでやり直す
                .task(id: auth.account?.uid) {
                    store.editorName = profile.displayName(for: auth.account)
                    if let uid = auth.account?.uid {
                        async let shared: Void = calendars.start(uid: uid)
                        await sync.start(uid: uid)
                        await shared
                        await WidgetSharedFeed.refresh(store: store, calendars: calendars.calendars, sharedView: sharedView)
                    } else {
                        sync.stop()
                        sharedView.close()
                        calendars.stop()
                    }
                    WidgetSync.publish(store: store)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await updater.check() }
                        sync.retryIfNeeded()
                        // 承認や参加者の変更など、閉じている間に変わった参加の状態を取り直す
                        Task {
                            await calendars.refresh()
                            // ウィジェットで見ている共有カレンダーの中身を、新しくする
                            await WidgetSharedFeed.refresh(store: store, calendars: calendars.calendars, sharedView: sharedView)
                        }
                        publisher.schedule()
                        if sharedView.isOpen { Task { await sharedView.refresh() } }
                    }
                }
                .onChange(of: startMonday) { WidgetSync.publish(store: store) }
                .onChange(of: profile.customName) { store.editorName = profile.displayName(for: auth.account) }
        }
    }
}
