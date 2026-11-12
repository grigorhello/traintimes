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

/// Settings (TT-105, redesigned in TT-168, D57): the two on-device choices, the Notifications row and page, About and the
/// Testing page of TestFlight and Debug builds.
@Observable @MainActor
final class SettingsViewModel {
    /// Pages on traintimes.ca (TT-151) and the official GO service updates page, opened in Safari.
    static let dataURL = URL(string: "https://traintimes.ca/data")!
    static let privacyURL = URL(string: "https://traintimes.ca/privacy")!
    static let officialUpdatesURL = URL(string: "https://www.gotransit.com/en/service-updates")!

    /// The Notifications row's dot: green while notifications are allowed, red once the rider turned them off in iOS
    /// Settings, grey while the app has never asked.
    enum NotificationDot: Equatable {
        case green, red, grey
    }

    let settings: AppSettings
    let appInfo: AppInfo
    /// The Testing page (Demo trains, Mock time) shows in TestFlight and Debug builds only (D49).
    let showsTesting: Bool
    /// nil until the first read from the system; refreshed each time Settings appears or the app returns to the foreground.
    var permission: NotificationPermission?
    private let permissions: any NotificationPermissionProviding
    /// The alert rules, for the Notifications page's "My alerts" count and its "Turn on notifications" button; nil in tests
    /// that need neither.
    private let alerts: AlertRules?
    /// The app's clock (with Mock time off, the device or fixture clock): Mock time starts from its "now".
    private let clock: any AppClock
    /// "Detect my train" (TT-176), the switch on the Notifications page; nil hides it (fixture runs, most tests).
    private let detection: BackgroundDetection?

    init(
        settings: AppSettings,
        permissions: any NotificationPermissionProviding = SystemNotificationPermission(),
        appInfo: AppInfo = .main,
        showsTesting: Bool = BuildChannel.showsTesting,
        clock: any AppClock = SystemClock(),
        alerts: AlertRules? = nil,
        detection: BackgroundDetection? = nil
    ) {
        self.settings = settings
        self.showsTesting = showsTesting
        self.permissions = permissions
        self.appInfo = appInfo
        self.clock = clock
        self.alerts = alerts
        self.detection = detection
    }

    var timeFormat: TimeFormat {
        get { settings.timeFormat }
        set { settings.timeFormat = newValue }
    }

    /// Delays, Offline and Platform make their own live status, so choosing one turns Live data off (TT-195).
    var demoTrains: DemoTrains {
        get { settings.demoTrains }
        set {
            settings.demoTrains = newValue
            if newValue.makesLiveStatus { settings.mockLive = .off }
        }
    }

    /// Settings › Testing › Live data (TT-195): choosing a feed turns off a Demo trains mode that makes its own.
    var mockLive: MockLive {
        get { settings.mockLive }
        set {
            settings.mockLive = newValue
            if newValue != .off, settings.demoTrains.makesLiveStatus { settings.demoTrains = .off }
        }
    }

    // MARK: Notifications

    /// The dot beside the Notifications row; nil until the permission has been read.
    var notificationDot: NotificationDot? {
        switch permission {
        case .allowed: .green
        case .off: .red
        case .notAsked: .grey
        case nil: nil
        }
    }

    /// "On" while allowed; "Off" for a denied or never asked permission.
    var notificationWord: String? {
        switch permission {
        case .allowed: String(localized: "settings.notifications.on")
        case .off, .notAsked: String(localized: "settings.notifications.off")
        case nil: nil
        }
    }

    /// "My alerts · N": every saved rule, paused or not.
    var alertCount: Int {
        alerts?.rules.count ?? 0
    }

    /// Alerts switched on and still in force: the number the off card speaks of, as on the Alerts tab (TT-169).
    var switchedOnCount: Int {
        alerts?.switchedOnCount(on: ServiceDay(containing: clock.now)) ?? 0
    }

    /// The app's page in the Settings app, where notifications are turned back on.
    var notificationSettingsURL: URL {
        URL(string: UIApplication.openNotificationSettingsURLString)!
    }

    func refreshPermission() async {
        permission = await permissions.current()
    }

    /// "Turn on notifications": the iOS prompt, once, through the alert rules (D41, revised by D57); the page and the row
    /// update with the answer.
    func turnOnNotifications() async {
        if let alerts {
            await alerts.requestPermission()
        } else {
            _ = await permissions.request()
        }
        await refreshPermission()
    }

    // MARK: Detect my train (TT-176)

    /// The switch shows: the app can detect trains (not in fixture runs).
    var showsDetection: Bool { detection != nil }

    /// "Detect my train": on asks iOS for Always (and for notifications if never asked), and goes back off without Always;
    /// off stops the wake-ups at once.
    var detectsTrain: Bool {
        get { detection?.isOn ?? false }
        set {
            guard let detection, newValue != detection.isOn else { return }
            if newValue {
                Task { await turnOnDetection() }
            } else {
                detection.turnOff()
            }
        }
    }

    /// Three Not me in a week turned it off: a line under the switch says so.
    var detectionWasTurnedOff: Bool { detection?.wasTurnedOff ?? false }

    func turnOnDetection() async {
        guard let detection, await detection.turnOn() else { return }
        if let alerts { await alerts.requestPermission() }
        await refreshPermission()
    }

    // MARK: Testing

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

    /// A quick choice: the picker's date at the preset's time. Always a fresh choice, even for the minute already set, so
    /// "Midnight" can be tapped again to run the day change again.
    func chooseMockTime(_ preset: MockTimePreset) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = goTimeZone
        let moment = calendar.date(bySettingHour: preset.hour, minute: preset.minute, second: 0, of: mockTimeStart)
        settings.mockTime = MockTimeSetting(start: moment ?? mockTimeStart, setAt: Date())
    }

    /// Anything on the Testing page is switched on: the row turns amber and Reset appears.
    var isTestingActive: Bool {
        demoTrains != .off || mockLive != .off || isMockTimeOn
    }

    /// The Testing row's value: "Off", or what is on, "Delays · Mock time".
    var testingValue: String {
        var parts: [String] = []
        switch demoTrains {
        case .off: break
        case .delays: parts.append(String(localized: "settings.demo_trains.delays"))
        case .offline: parts.append(String(localized: "settings.demo_trains.offline"))
        case .awaitingPlatform: parts.append(String(localized: "settings.demo_trains.platform"))
        case .ride: parts.append(String(localized: "settings.demo_trains.ride"))
        case .departure: parts.append(String(localized: "settings.demo_trains.departure"))
        }
        if let live = mockLive.labelKey {
            let word = String(localized: String.LocalizationValue(live))
            parts.append(String(format: String(localized: "settings.live_data.value"), word))
        }
        if isMockTimeOn { parts.append(String(localized: "settings.mock_time")) }
        return parts.isEmpty ? String(localized: "settings.testing.off") : parts.joined(separator: " · ")
    }

    /// "Reset": Demo trains and Live data off and the real time.
    func resetTesting() {
        demoTrains = .off
        mockLive = .off
        settings.mockTime = nil
    }

    // MARK: About

    /// The About row's value, "1.0 (12)".
    var versionValue: String {
        String(format: String(localized: "settings.version_value"), appInfo.version, appInfo.build)
    }

    /// The About page's pill, "Version 1.0 (12)".
    var versionLine: String {
        String(format: String(localized: "settings.version"), appInfo.version, appInfo.build)
    }
}

extension DemoTrains {
    /// Delays, Offline and Platform make their own live status; the others leave it to the feed or to Live data (TT-195).
    var makesLiveStatus: Bool {
        switch self {
        case .delays, .offline, .awaitingPlatform: true
        case .off, .ride, .departure: false
        }
    }
}

extension MockLive {
    /// The word on the switch, nil for Off.
    var labelKey: String? {
        switch self {
        case .off: nil
        case .onTime: "settings.live_data.on_time"
        case .mixed: "settings.live_data.mixed"
        case .changing: "settings.live_data.changing"
        case .stale: "settings.live_data.stale"
        }
    }
}
