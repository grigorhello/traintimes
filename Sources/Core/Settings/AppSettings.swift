import Foundation
import Observation

/// Time format and the Testing switches, stored on device (TT-105). One instance, owned by the root view.
/// The root puts `timeFormatter` in the environment, so a change applies at once. The app follows the iOS appearance (D84).
@Observable @MainActor
final class AppSettings {
    static let timeFormatKey = "settings.timeFormat"

    var timeFormat: TimeFormat {
        didSet {
            defaults.set(timeFormat.rawValue, forKey: Self.timeFormatKey)
            if timeFormat != oldValue { Analytics.track(.settingChanged("time_format", value: timeFormat.rawValue)) }
        }
    }

    /// Settings › Testing › Demo trains (D49), shown in TestFlight and Debug builds only.
    var demoTrains: DemoTrains {
        didSet { defaults.set(demoTrains.rawValue, forKey: DemoTrains.key) }
    }

    /// Settings › Testing › Live data (TT-195), shown in TestFlight and Debug builds only.
    var mockLive: MockLive {
        didSet { defaults.set(mockLive.rawValue, forKey: MockLive.key) }
    }

    /// Settings › Testing › Mock time (TT-158, D51), shown in TestFlight and Debug builds only; nil is the real time.
    var mockTime: MockTimeSetting? {
        // Written only when it differs from what is stored, so reading it at launch (a launch argument, the stored value)
        // never writes it back: a UI test's Mock time must not stay on the simulator for the next test.
        didSet {
            guard mockTime != MockTime.read(from: defaults) else { return }
            MockTime.write(mockTime, to: defaults)
        }
    }

    /// Settings › Testing › Demo weather (TT-226): fixture weather on the weather tile; TestFlight and Debug builds only.
    var demoWeather: Bool {
        didSet { demoWeather ? defaults.set("on", forKey: DemoWeather.key) : defaults.removeObject(forKey: DemoWeather.key) }
    }

    /// The one formatter (D17), following the Time format setting.
    var timeFormatter: TimeFormatter { TimeFormatter(format: timeFormat) }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        timeFormat = defaults.string(forKey: Self.timeFormatKey).flatMap(TimeFormat.init(rawValue:)) ?? .device
        demoTrains = defaults.string(forKey: DemoTrains.key).flatMap(DemoTrains.init(rawValue:)) ?? .off
        mockLive = defaults.string(forKey: MockLive.key).flatMap(MockLive.init(rawValue:)) ?? .off
        mockTime = MockTime.read(from: defaults)
        demoWeather = defaults.string(forKey: DemoWeather.key) == "on"
    }
}
