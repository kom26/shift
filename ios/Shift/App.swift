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
    @Environment(\.scenePhase) private var scenePhase

    init() {
        AppFont.register()
        FirebaseApp.configure()
        let s = Store()
        let a = AccountSync(store: s, backing: FirestoreBacking())
        let cal = CalendarService(backing: FirestoreCalendarBacking())
        let eventsBacking = FirestoreSharedEvents()
        let pub = SharedPublisher(backing: eventsBacking, store: s,
                                  calendars: { [weak cal] in cal?.calendars ?? [] }, uid: { [weak cal] in cal?.myUid })
        cal.onChange = { [weak pub] in pub?.schedule() }
        s.onLocalChange = { [weak a, weak s, weak pub] in
            a?.localChanged()
            pub?.schedule()
            if let s { WidgetSync.publish(store: s) }
        }
        a.onApplied = { [weak s] in
            guard let s else { return }
            WidgetSync.publish(store: s)
            Task { await AlarmService.shared.refresh(store: s) }
        }
        _store = State(initialValue: s)
        _sync = State(initialValue: a)
        _auth = State(initialValue: AuthService())
        _calendars = State(initialValue: cal)
        _publisher = State(initialValue: pub)
        _sharedView = State(initialValue: SharedViewState(events: eventsBacking, calendars: cal))
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
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
                .tint(Theme.accent)
                .overlay {
                    if sync.status.restoring || sync.status.choice != nil { RestoringOverlay(sync: sync) }
                }
                // ログインしている間だけ同期する。ログアウトや別のアカウントへの切り替えでやり直す
                .task(id: auth.account?.uid) {
                    if let uid = auth.account?.uid {
                        async let shared: Void = calendars.start(uid: uid)
                        await sync.start(uid: uid)
                        await shared
                    } else {
                        sync.stop()
                        sharedView.close()
                        calendars.stop()
                    }
                    WidgetSync.publish(store: store)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        sync.retryIfNeeded()
                        publisher.schedule()
                        if sharedView.isOpen { Task { await sharedView.refresh() } }
                    }
                }
                .onChange(of: startMonday) { WidgetSync.publish(store: store) }
        }
    }
}
