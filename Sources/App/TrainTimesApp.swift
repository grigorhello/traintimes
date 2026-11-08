import SwiftUI

@main
struct TrainTimesApp: App {
    /// Notification taps reach the router through it, also when a tap launches the app (TT-144), and so does the APNs
    /// device token for alerts (TT-141).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView(router: appDelegate.router)
        }
    }
}
