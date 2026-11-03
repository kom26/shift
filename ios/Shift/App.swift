import FirebaseCore
import GoogleSignIn
import SwiftUI

@main
struct ShiftApp: App {
    @State private var store = Store()
    @State private var holidays = Holidays()
    @State private var sync: CloudSync?
    @State private var syncStatus = SyncStatus()
    @AppStorage("startMonday") private var startMonday = false

    @State private var auth: AuthService

    init() {
        AppFont.register()
        FirebaseApp.configure()
        _auth = State(initialValue: AuthService())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.font, .app(17))
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .environment(store)
                .environment(holidays)
                .environment(auth)
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
                .tint(Theme.accent)
                .overlay {
                    if syncStatus.restoring { RestoringOverlay() }
                }
                .task {
                    guard sync == nil else { return }
                    let s = CloudSync(store: store, status: syncStatus)
                    store.onLocalChange = { [weak s] in
                        s?.localChanged()
                        WidgetSync.publish(store: store)
                    }
                    s.onApplied = {
                        WidgetSync.publish(store: store)
                        Task { await AlarmService.shared.refresh(store: store) }
                    }
                    sync = s
                    s.start()
                    WidgetSync.publish(store: store)
                }
                .onChange(of: startMonday) { WidgetSync.publish(store: store) }
        }
    }
}
