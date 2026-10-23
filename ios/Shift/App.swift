import SwiftUI

@main
struct ShiftApp: App {
    @State private var store = Store()
    @State private var holidays = Holidays()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(holidays)
                .tint(Theme.accent)
        }
    }
}
