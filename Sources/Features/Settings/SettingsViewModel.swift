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
    /// The app's clock (with Mock time off, the device or fixture clock): Mock time starts from its "now".
    private let clock: any AppClock

    init(
        settings: AppSettings,
        permissions: any NotificationPermissionProviding = SystemNotificationPermission(),
        appInfo: AppInfo = .main,
        showsTesting: Bool = BuildChannel.showsTesting,
        clock: any AppClock = SystemClock()
    ) {
        self.settings = settings
        self.showsTesting = showsTesting
        self.permissions = permissions
        self.appInfo = appInfo
        self.clock = clock
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

    /// Mock time (TT-158, D51): Off pretends nothing; On starts from the app's current time.
    var isMockTimeOn: Bool {
        get { settings.mockTime != nil }
        set { settings.mockTime = newValue ? MockTimeSetting(start: clock.now, setAt: Date()) : nil }
    }

    /// The moment the app pretends it is, at the moment it was chosen; the picker's value. Toronto time, as Schedule reads it.
    var mockTimeStart: Date {
        get { settings.mockTime?.start ?? clock.now }
        set {
            // The picker can hand back the value it was given, or the same minute; neither is a choice.
            if let current = settings.mockTime?.start, Self.sameMinute(current, newValue) { return }
            settings.mockTime = MockTimeSetting(start: newValue, setAt: Date())
        }
    }

    private static func sameMinute(_ a: Date, _ b: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = goTimeZone
        return calendar.isDate(a, equalTo: b, toGranularity: .minute)
    }

    /// A quick choice: the picker's date at the preset's time.
    func chooseMockTime(_ preset: MockTimePreset) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = goTimeZone
        let moment = calendar.date(bySettingHour: preset.hour, minute: preset.minute, second: 0, of: mockTimeStart)
        mockTimeStart = moment ?? mockTimeStart
    }

    /// "Use real time".
    func useRealTime() {
        settings.mockTime = nil
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
