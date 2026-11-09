import Foundation
import Observation

/// The Appearance setting (Settings, TT-105). Raw values are what the setting stores on device.
enum Appearance: String, CaseIterable, Sendable {
    case system
    case light
    case dark
}

/// Appearance and Time format, stored on device (TT-105). One instance, owned by the root view.
/// The root applies `appearance` and puts `timeFormatter` in the environment, so a change applies at once.
@Observable @MainActor
final class AppSettings {
    static let appearanceKey = "settings.appearance"
    static let timeFormatKey = "settings.timeFormat"

    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    var timeFormat: TimeFormat {
        didSet { defaults.set(timeFormat.rawValue, forKey: Self.timeFormatKey) }
    }

    /// Settings › Testing › Demo trains (D49), shown in TestFlight and Debug builds only.
    var demoTrains: DemoTrains {
        didSet { defaults.set(demoTrains.rawValue, forKey: DemoTrains.key) }
    }

    /// Settings › Testing › Mock time (TT-158, D51), shown in TestFlight and Debug builds only; nil is the real time.
    var mockTime: MockTimeSetting? {
        didSet { MockTime.write(mockTime, to: defaults) }
    }

    /// The one formatter (D17), following the Time format setting.
    var timeFormatter: TimeFormatter { TimeFormatter(format: timeFormat) }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Self.appearanceKey).flatMap(Appearance.init(rawValue:)) ?? .system
        timeFormat = defaults.string(forKey: Self.timeFormatKey).flatMap(TimeFormat.init(rawValue:)) ?? .device
        demoTrains = defaults.string(forKey: DemoTrains.key).flatMap(DemoTrains.init(rawValue:)) ?? .off
        mockTime = MockTime.read(from: defaults)
    }
}
