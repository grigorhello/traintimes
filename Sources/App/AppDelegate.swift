import UIKit

/// Forwards the APNs registration callbacks to `SystemPushRegistration` (TT-141).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        SystemPushRegistration.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        SystemPushRegistration.shared.didFail(error)
    }
}
