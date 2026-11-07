import SwiftUI

@main
struct TrainTimesApp: App {
    /// The APNs device token for alerts (TT-141).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
