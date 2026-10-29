import SwiftUI

@main
struct ShiftApp: App {
    @State private var store = Store()
    @State private var holidays = Holidays()
    @State private var sync: CloudSync?
    @AppStorage("startMonday") private var startMonday = false

    init() {
        AppFont.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.font, .app(17))
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .environment(store)
                .environment(holidays)
                .tint(Theme.accent)
                .task {
                    guard sync == nil else { return }
                    let s = CloudSync(store: store)
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
