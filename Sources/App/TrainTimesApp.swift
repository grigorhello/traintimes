import SwiftUI

@main
struct TrainTimesApp: App {
    /// Notification taps reach the router through it, also when a tap launches the app (TT-144), and so does the APNs
    /// device token for alerts (TT-141). It holds the app's one ride engine (TT-171), which On board shows (TT-172), the
    /// engine's arriving nudge (TT-173), its Live Activity (TT-174), "Detect my train" (TT-176) and the ride that starts by itself
    /// (TT-242).
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView(
                router: appDelegate.router, ride: appDelegate.ride, nudge: appDelegate.nudge,
                liveActivity: appDelegate.liveActivity, detection: appDelegate.detection, autoRide: appDelegate.autoRide
            )
        }
    }
}
