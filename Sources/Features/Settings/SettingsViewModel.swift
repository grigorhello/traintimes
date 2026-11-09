import Foundation
import Observation
import UIKit

/// Version and build from the bundle, for Settings › About.
struct AppInfo: Equatable, Sendable {
    var version: String
    var build: String

    static var main: AppInfo {
        AppInfo(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        )
    }
}

/// Settings (TT-105): the two on-device choices, the notification permission in words, the data and privacy links, About.
@Observable @MainActor
final class SettingsViewModel {
    /// Pages on traintimes.ca (TT-151) and the official GO service updates page, opened in Safari.
    static let dataURL = URL(string: "https://traintimes.ca/data")!
    static let privacyURL = URL(string: "https://traintimes.ca/privacy")!
    static let officialUpdatesURL = URL(string: "https://www.gotransit.com/en/service-updates")!

    let settings: AppSettings
    let appInfo: AppInfo
    /// The Testing section (Demo trains) shows in TestFlight and Debug builds only (D49).
    let showsTesting: Bool
    /// nil until the first read from the system; refreshed each time Settings appears or the app returns to the foreground.
    var permission: NotificationPermission?
    private let permissions: any NotificationPermissionProviding

    init(
        settings: AppSettings,
        permissions: any NotificationPermissionProviding = SystemNotificationPermission(),
        appInfo: AppInfo = .main,
        showsTesting: Bool = BuildChannel.showsTesting
    ) {
        self.settings = settings
        self.showsTesting = showsTesting
        self.permissions = permissions
        self.appInfo = appInfo
    }

    var appearance: Appearance {
        get { settings.appearance }
        set { settings.appearance = newValue }
    }

    var timeFormat: TimeFormat {
        get { settings.timeFormat }
        set { settings.timeFormat = newValue }
    }

    var demoTrains: DemoTrains {
        get { settings.demoTrains }
        set { settings.demoTrains = newValue }
    }

    /// "Version 1.0 (1) · Your next GO train, at a glance."
    var versionLine: String {
        String(format: String(localized: "settings.version"), appInfo.version, appInfo.build)
    }

    /// The app's page in the Settings app, where notifications are turned back on.
    var notificationSettingsURL: URL {
        URL(string: UIApplication.openNotificationSettingsURLString)!
    }

    func refreshPermission() async {
        permission = await permissions.current()
    }
}
