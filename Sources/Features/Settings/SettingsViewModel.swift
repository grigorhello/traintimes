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

/// One station on Settings › Testing › Demo place's switch (TT-234, D116): its id and its short name.
struct DemoPlaceStation: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
}

/// Settings (TT-105, redesigned in TT-168, D57): the two on-device choices, the Notifications row and page, the Automatic
/// card (Automatic direction, TT-234, D116; Automatic ride and When the app is closed, TT-243, D120), About and the Testing
/// page of TestFlight and Debug builds.
@Observable @MainActor
final class SettingsViewModel {
    /// Pages on traintimes.ca (TT-151) and the official GO service updates page, opened in Safari.
    static let dataURL = URL(string: "https://traintimes.ca/data")!
    static let privacyURL = URL(string: "https://traintimes.ca/privacy")!
    static let officialUpdatesURL = URL(string: "https://www.gotransit.com/en/service-updates")!
    /// The app's page in the Settings app, where location and Precise Location are allowed (TT-234, D116).
    static let locationSettingsURL = URL(string: UIApplication.openSettingsURLString)!

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
    /// Automatic ride's "off" and When the app is closed's "on" (TT-243, D120); nil (previews, most tests) reads both off.
    private let autoRideStore: AutoRideStore?
    /// When the app is closed: Always and the wake-ups; nil hides the row (fixture runs, previews, most tests).
    private let autoRideWake: AutoRideWake?
    /// The one-time strip on Schedule, drawn again when Automatic ride changes here.
    private let autoRideStrip: AutoRideStrip?
    /// Done when "Turn on notifications" turned them on (TT-215, D100).
    private let haptics: any HapticPlaying
    /// Automatic direction's location reader and what it keeps on device (TT-234, D116). With either missing (previews,
    /// most tests) the switch reads off and a tap does nothing, as with a reader that is `.unavailable` (fixture runs).
    private let direction: (any DirectionLocating)?
    private let directionStore: DirectionStore?
    /// The look, for Settings › Testing › Last look.
    private let look: DirectionLook?
    /// Schedule's route: Demo place is one of its two stations.
    private let route: @MainActor () -> Route?
    /// How the automatic ride's last watch ended (TT-242, D120), for Settings › Testing › Last check; nil before any.
    private let autoRideCheck: @MainActor () -> AutoRideCheck?
    /// Where Demo place is stored: the app's defaults, as `AppSettings` stores Demo trains; tests pass their own.
    private let defaults: UserDefaults
    /// Opens a page of the Settings app, as the Notifications page does with `openURL`; tests record the page instead.
    private let openSettings: @MainActor (URL) -> Void
    /// Bumped when the location permission, the stored "off" or Demo place may have changed. The reader is not observed,
    /// so the Automatic direction switch and its note read this to be drawn again.
    private var directionReads = 0
    /// The stored Demo place, whichever route shows.
    private var storedDemoPlace: String?

    init(
        settings: AppSettings,
        permissions: any NotificationPermissionProviding = SystemNotificationPermission(),
        appInfo: AppInfo = .main,
        showsTesting: Bool = BuildChannel.showsTesting,
        clock: any AppClock = SystemClock(),
        alerts: AlertRules? = nil,
        autoRideStore: AutoRideStore? = nil,
        autoRideWake: AutoRideWake? = nil,
        autoRideStrip: AutoRideStrip? = nil,
        haptics: any HapticPlaying = TTHaptics.shared,
        direction: (any DirectionLocating)? = nil,
        directionStore: DirectionStore? = nil,
        look: DirectionLook? = nil,
        route: @escaping @MainActor () -> Route? = { nil },
        autoRideCheck: @escaping @MainActor () -> AutoRideCheck? = { nil },
        defaults: UserDefaults = .standard,
        openSettings: @escaping @MainActor (URL) -> Void = { UIApplication.shared.open($0, options: [:], completionHandler: nil) }
    ) {
        self.haptics = haptics
        self.settings = settings
        self.showsTesting = showsTesting
        self.permissions = permissions
        self.appInfo = appInfo
        self.clock = clock
        self.alerts = alerts
        self.autoRideStore = autoRideStore
        self.autoRideWake = autoRideWake
        self.autoRideStrip = autoRideStrip
        self.direction = direction
        self.directionStore = directionStore
        self.look = look
        self.route = route
        self.autoRideCheck = autoRideCheck
        self.defaults = defaults
        self.openSettings = openSettings
        storedDemoPlace = defaults.string(forKey: DemoPlace.key).flatMap { $0.isEmpty ? nil : $0 }
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

    /// Settings › Testing › Express (TT-232): the demo ride, from Ride's question or Depart's "I’m on board", is the express
    /// that does not stop between Union and Clarkson. The switch shows with those two modes.
    var demoExpress: Bool {
        get { settings.demoExpress }
        set { settings.demoExpress = newValue }
    }

    var showsDemoExpress: Bool { demoTrains == .ride || demoTrains == .departure }

    /// Settings › Testing › Demo trains › Depart › Automatic ride (TT-242, D120): the demo watch decides whether the phone
    /// left with the demo departure's train. The switch shows with Depart only.
    var demoAutoRide: DemoAutoRide {
        get { settings.demoAutoRide }
        set { settings.demoAutoRide = newValue }
    }

    var showsDemoAutoRide: Bool { demoTrains == .departure }

    /// Settings › Testing › Live data (TT-195): choosing a feed turns off a Demo trains mode that makes its own.
    var mockLive: MockLive {
        get { settings.mockLive }
        set {
            settings.mockLive = newValue
            if newValue != .off, settings.demoTrains.makesLiveStatus { settings.demoTrains = .off }
        }
    }

    /// Settings › Testing › Demo weather (TT-226).
    var isDemoWeatherOn: Bool {
        get { settings.demoWeather }
        set { settings.demoWeather = newValue }
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

    /// Reads the notification permission, and has the Automatic direction switch read the location permission again
    /// (TT-234): at once, and once more after the wait, when iOS has had a moment to hand over a change made in the
    /// Settings app.
    func refreshPermission() async {
        directionReads += 1
        permission = await permissions.current()
        directionReads += 1
    }

    /// "Turn on notifications": the iOS prompt, once, through the alert rules (D41, revised by D57); the page and the row
    /// update with the answer.
    func turnOnNotifications() async {
        if let alerts {
            await alerts.requestPermission()
        } else {
            _ = await permissions.request()
        }
        let was = permission
        await refreshPermission()
        if permission == .allowed, was != .allowed { haptics.play(.confirmed) }
    }

    // MARK: Automatic direction (TT-234, D116)

    /// The reader and the store, where Automatic direction can work; nil in fixture runs, previews and the unit test host.
    private var directionReader: (location: any DirectionLocating, store: DirectionStore)? {
        guard let direction, let directionStore, direction.permission != .unavailable else { return nil }
        return (direction, directionStore)
    }

    /// The Automatic direction switch. It reads on while location is allowed with Precise Location, unless the rider
    /// turned it off: only that "off" is stored. Setting it is the rider's tap (`tapAutoDirection(_:)`).
    var autoDirection: Bool {
        get {
            _ = directionReads
            guard let reader = directionReader else { return false }
            return reader.location.readsOn(reader.store)
        }
        set { tapAutoDirection(newValue) }
    }

    /// The one note under the Automatic card, as its key in the strings file, the first that applies: what iOS keeps
    /// Automatic direction and Automatic ride from (location refused, Precise Location off), that two Not on it turned
    /// Automatic ride off (until it is turned on again, TT-243), else what the card does.
    var automaticNote: String {
        _ = directionReads
        if let location = directionReader?.location {
            switch location.permission {
            case .refused: return "settings.auto_direction.needs_location"
            case .allowed where !location.isPrecise: return "settings.auto_direction.needs_precise"
            case .allowed, .notAsked, .unavailable: break
            }
        }
        if let autoRideStore, autoRideStore.isOff, autoRideStore.turnedOffAt != nil { return "settings.auto_ride.turned_off" }
        return "settings.automatic.note"
    }

    /// The rider's tap on the switch. Off stores the "off". On clears it, and then: location never asked (or Allow Once
    /// ran out) shows the iOS prompt at once; location refused, or Precise Location off, opens the app's page in the
    /// Settings app and the switch stays off. Everything but the prompt is done before the switch is drawn again, so it
    /// never jumps back under the finger. Returns the task that waits for the prompt's answer, nil when none was shown.
    @discardableResult
    func tapAutoDirection(_ on: Bool) -> Task<Void, Never>? {
        guard let reader = directionReader else {
            autoDirectionSettled(from: false)
            return nil
        }
        let was = reader.location.readsOn(reader.store)
        var prompt: Task<Void, Never>?
        if on {
            reader.store.isOff = false
            switch reader.location.permission {
            case .notAsked:
                prompt = Task {
                    _ = await self.direction?.requestWhenInUse()
                    self.autoDirectionSettled(from: was)
                }
            case .refused:
                openSettings(Self.locationSettingsURL)
            case .allowed:
                if !reader.location.isPrecise { openSettings(Self.locationSettingsURL) }
            case .unavailable:
                break
            }
        } else if was {
            reader.store.isOff = true
            // An unanswered one-time strip on Schedule goes and counts as answered (TT-236).
            look?.turnedOffInSettings()
        }
        if prompt == nil { autoDirectionSettled(from: was) }
        return prompt
    }

    /// A tap is done. `setting_changed` is sent only when it left the switch changed: not when iOS refuses, not when the
    /// tap only opened the Settings app, and never when the permission alone changes the switch. The switch is drawn
    /// again either way, so one the tap could not change goes back.
    private func autoDirectionSettled(from was: Bool) {
        directionReads += 1
        let isOn = autoDirection
        if isOn != was { Analytics.track(.settingChanged("auto_direction", value: isOn ? "on" : "off")) }
    }

    // MARK: Automatic ride (TT-243, D120)

    /// A Demo Automatic ride mode is set (TT-242): the switch reads on with no location, as the demo watch needs none.
    private var demoAutoRideOn: Bool { showsTesting && settings.demoAutoRide != .off }

    /// The reader and the store, where Automatic ride can work; nil in previews and most tests, and in fixture runs with no
    /// demo mode.
    private var autoRideReader: (location: any DirectionLocating, store: AutoRideStore)? {
        guard let direction, let autoRideStore, direction.permission != .unavailable || demoAutoRideOn else { return nil }
        return (direction, autoRideStore)
    }

    /// The Automatic ride switch. It reads on while location is allowed with Precise Location (or a Demo Automatic ride mode
    /// is set), unless the rider turned it off: only that "off" is stored (`AutoRideStore.isOff`). Setting it is the
    /// rider's tap (`tapAutoRide(_:)`).
    var autoRide: Bool {
        get {
            _ = directionReads
            guard let reader = autoRideReader else { return false }
            return reader.location.readsOn(reader.store, demo: demoAutoRideOn)
        }
        set { tapAutoRide(newValue) }
    }

    /// The rider's tap on Automatic ride. Off stores the "off" (an unanswered one-time strip counts as answered, as D116's
    /// does). On clears it, with two Not on it's note and count, and then: location never asked shows the When In Use
    /// prompt at once; refused, or Precise Location off, opens the app's page in the Settings app and the switch stays
    /// off. Returns the task that waits for the prompt's answer, nil when none was shown.
    @discardableResult
    func tapAutoRide(_ on: Bool) -> Task<Void, Never>? {
        guard let reader = autoRideReader else {
            autoRideSettled(from: false)
            return nil
        }
        let was = reader.location.readsOn(reader.store, demo: demoAutoRideOn)
        var prompt: Task<Void, Never>?
        if on {
            reader.store.turnOn()
            if !demoAutoRideOn {
                switch reader.location.permission {
                case .notAsked:
                    prompt = Task {
                        _ = await self.direction?.requestWhenInUse()
                        self.autoRideSettled(from: was)
                    }
                case .refused:
                    openSettings(Self.locationSettingsURL)
                case .allowed:
                    if !reader.location.isPrecise { openSettings(Self.locationSettingsURL) }
                case .unavailable:
                    break
                }
            }
        } else if was {
            reader.store.isOff = true
            if reader.store.stripDue { reader.store.stripAnswered = true }
        }
        if prompt == nil { autoRideSettled(from: was) }
        return prompt
    }

    /// A tap on Automatic ride is done: `setting_changed` only when it left the switch changed, and the strip and the
    /// wake-ups follow.
    private func autoRideSettled(from was: Bool) {
        directionReads += 1
        let isOn = autoRide
        if isOn != was { Analytics.track(.settingChanged("auto_ride", value: isOn ? "on" : "off")) }
        autoRideStrip?.refresh()
        autoRideWake?.resume()
    }

    /// When the app is closed shows while Automatic ride reads on, where the app has wake-ups (not in fixture runs).
    var showsAutoRideClosed: Bool { autoRideWake != nil && autoRide }

    /// When the app is closed: on only with Always allowed and the rider's own "on" (off by default); Always taken back
    /// reads off. Setting it is the rider's tap (`tapAutoRideClosed(_:)`).
    var autoRideClosed: Bool {
        get {
            _ = directionReads
            return autoRideWake?.isOn ?? false
        }
        set { tapAutoRideClosed(newValue) }
    }

    /// The rider's tap on When the app is closed. On keeps the rider's "on" at once, then with Always not allowed shows
    /// iOS's prompts (When In Use first where location was never asked, then Always) where iOS still can, and otherwise
    /// opens the app's page in the Settings app, the switch staying off. Off stops the wake-ups. Returns the task that
    /// waits for the prompts, nil when none was shown.
    @discardableResult
    func tapAutoRideClosed(_ on: Bool) -> Task<Void, Never>? {
        guard let wake = autoRideWake else { return nil }
        let was = wake.isOn
        var prompt: Task<Void, Never>?
        if on {
            if !wake.switchOn() {
                if wake.canAskAlways {
                    prompt = Task {
                        _ = await wake.turnOn()
                        self.autoRideClosedSettled(from: was)
                    }
                } else {
                    openSettings(Self.locationSettingsURL)
                }
            }
        } else if was {
            wake.turnOff()
        }
        if prompt == nil { autoRideClosedSettled(from: was) }
        return prompt
    }

    private func autoRideClosedSettled(from was: Bool) {
        directionReads += 1
        let isOn = autoRideClosed
        if isOn != was { Analytics.track(.settingChanged("auto_ride_closed", value: isOn ? "on" : "off")) }
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

    /// Settings › Testing › Demo place (TT-234, D116): the station Automatic direction reads the phone as at, by id; nil
    /// is Off. It is stored under `DemoPlace.key`, where `DemoPlaceLocation` reads it; a stored id that is neither of the
    /// route's two stations reads Off.
    var demoPlace: String? {
        get { DemoPlace.station(on: route(), stored: storedDemoPlace) }
        set {
            storedDemoPlace = newValue
            if let newValue {
                defaults.set(newValue, forKey: DemoPlace.key)
            } else {
                defaults.removeObject(forKey: DemoPlace.key)
            }
            // A demo place counts as location allowed, so the Automatic direction switch reads again.
            directionReads += 1
        }
    }

    /// The stations on the Demo place switch: the route's two, From first, by their short names; none without a route.
    var demoPlaceStations: [DemoPlaceStation] {
        guard let route = route() else { return [] }
        return [route.from, route.to].map { DemoPlaceStation(id: $0.id, name: StationNames.short($0.name)) }
    }

    /// Settings › Testing › Last look (TT-234, D116): how long the last look waited and what it did.
    var lastLookText: String {
        Self.lastLookText(look?.lastLook)
    }

    /// A look in words: the seconds it waited, with one decimal, and what it did, with the reason when it did nothing.
    /// Never a place.
    static func lastLookText(_ last: DirectionLook.LastLook?) -> String {
        guard let last else { return String(localized: "settings.last_look.none") }
        let seconds = String(format: "%.1f", last.waited)
        switch last.outcome {
        case .turn:
            return String(format: String(localized: "settings.last_look.turn"), seconds)
        case .ask:
            return String(format: String(localized: "settings.last_look.ask"), seconds)
        case .nothing(let reason):
            let key = "settings.last_look.reason." + reason.rawValue
            let why = String(localized: String.LocalizationValue(key))
            return String(format: String(localized: "settings.last_look.nothing"), seconds, why)
        }
    }

    /// Settings › Testing › Last check (TT-242, D120): how the automatic ride's last watch ended. The view passes the
    /// formatter it reads from the environment, so a Time format change shows at once.
    func lastCheckText(formatter: any TimeFormatting) -> String {
        Self.lastCheckText(autoRideCheck(), formatter: formatter)
    }

    /// A check in words: the outcome, with the whole seconds after the train left (0 when it had not left) and, when it
    /// could not tell, the reason; then, on a second line, when the hold reached the server. Never a place.
    static func lastCheckText(_ check: AutoRideCheck?, formatter: any TimeFormatting) -> String {
        guard let check else { return String(localized: "settings.last_check.none") }
        let seconds = String(check.secondsAfter ?? 0)
        var text: String
        switch check.outcome {
        case .started:
            text = String(format: String(localized: "settings.last_check.started"), seconds)
        case .notOnBoard:
            text = String(format: String(localized: "settings.last_check.not_on_board"), seconds)
        case .unsure:
            if let reason = check.reason {
                let why = String(localized: String.LocalizationValue("settings.last_check.reason." + reason.rawValue))
                text = String(format: String(localized: "settings.last_check.unsure"), seconds, why)
            } else {
                // Ended with no verdict (a relaunch past its deadline, or a train that never read as left).
                text = String(format: String(localized: "settings.last_check.unsure_plain"), seconds)
            }
        case .answered:
            text = String(localized: "settings.last_check.answered")
        case .stopped:
            text = String(localized: "settings.last_check.stopped")
        case .notArmed:
            text = String(localized: "settings.last_check.not_armed")
        }
        if let hold = check.holdReachedAt {
            text += "\n" + String(format: String(localized: "settings.last_check.hold"), formatter.time(hold))
        }
        return text
    }

    /// Anything on the Testing page is switched on: the row turns amber and Reset appears.
    var isTestingActive: Bool {
        demoTrains != .off || mockLive != .off || demoPlace != nil || isMockTimeOn || isDemoWeatherOn
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
        // Automatic ride counts only under Depart: with another mode its stored choice plays nothing.
        if showsDemoAutoRide, demoAutoRide != .off { parts.append(String(localized: "settings.demo_auto_ride")) }
        if let live = mockLive.labelKey {
            let word = String(localized: String.LocalizationValue(live))
            parts.append(String(format: String(localized: "settings.live_data.value"), word))
        }
        if demoPlace != nil { parts.append(String(localized: "settings.demo_place")) }
        if isMockTimeOn { parts.append(String(localized: "settings.mock_time")) }
        if isDemoWeatherOn { parts.append(String(localized: "settings.demo_weather")) }
        return parts.isEmpty ? String(localized: "settings.testing.off") : parts.joined(separator: " · ")
    }

    /// "Reset": Demo trains (with Express and Automatic ride), Live data and Demo place off and the real time.
    func resetTesting() {
        demoTrains = .off
        demoExpress = false
        demoAutoRide = .off
        mockLive = .off
        if storedDemoPlace != nil { demoPlace = nil }
        settings.mockTime = nil
        isDemoWeatherOn = false
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
        case .boarding: "settings.live_data.boarding"
        }
    }
}
