import SwiftUI

@main
struct TrainTimesApp: App {
    /// Notification taps reach the router through it, also when a tap launches the app (TT-144).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView(router: appDelegate.router)
        }
    }
}
