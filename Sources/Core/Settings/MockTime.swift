import Foundation

/// Settings › Testing › Mock time (TT-158, D51), for TestFlight and Debug builds: the app pretends it is `start` and keeps
/// running from there, so the timeline can be checked early, late and across midnight without waiting.
struct MockTimeSetting: Equatable, Sendable {
    /// The moment the app pretends it is, at the moment of choosing.
    var start: Date
    /// The real moment it was chosen; the mocked clock runs on from `start` by the real time since.
    var setAt: Date

    func now(real: Date) -> Date {
        start.addingTimeInterval(max(0, real.timeIntervalSince(setAt)))
    }
}

/// How Mock time is stored on device: two numbers in UserDefaults (seconds since 1970), so a UI test can set it with the
/// launch argument `-settings.mockTime <seconds>`. A launch argument has no `setAt`, so it runs from the start of the run.
enum MockTime {
    static let startKey = "settings.mockTime"
    static let setAtKey = "settings.mockTimeSetAt"

    /// When this run began (first read, at launch).
    static let processStart = Date()

    static func read(from defaults: UserDefaults) -> MockTimeSetting? {
        let start = defaults.double(forKey: startKey)
        guard start > 0 else { return nil }
        let setAt = defaults.double(forKey: setAtKey)
        return MockTimeSetting(
            start: Date(timeIntervalSince1970: start), setAt: setAt > 0 ? Date(timeIntervalSince1970: setAt) : processStart
        )
    }

    static func write(_ setting: MockTimeSetting?, to defaults: UserDefaults) {
        if let setting {
            defaults.set(setting.start.timeIntervalSince1970, forKey: startKey)
            defaults.set(setting.setAt.timeIntervalSince1970, forKey: setAtKey)
        } else {
            defaults.removeObject(forKey: startKey)
            defaults.removeObject(forKey: setAtKey)
        }
    }

    /// The stored setting, read from the standard defaults, so the clock can read it from any thread.
    static var stored: MockTimeSetting? { read(from: .standard) }
}

/// Quick choices in the Testing section: the cases Grigor named, each on the date shown in the picker.
enum MockTimePreset: CaseIterable, Sendable {
    /// Before the first train.
    case early
    /// After the evening peak.
    case late
    /// Two minutes before midnight, so the day changes while the screen is open.
    case dayChange

    var hour: Int {
        switch self {
        case .early: 5
        case .late, .dayChange: 23
        }
    }

    var minute: Int {
        switch self {
        case .early: 0
        case .late: 45
        case .dayChange: 58
        }
    }

    var titleKey: String {
        switch self {
        case .early: "settings.mock_time.early"
        case .late: "settings.mock_time.late"
        case .dayChange: "settings.mock_time.day_change"
        }
    }

    var identifier: String {
        switch self {
        case .early: "settings.mockTime.early"
        case .late: "settings.mockTime.late"
        case .dayChange: "settings.mockTime.dayChange"
        }
    }
}

/// The clock with Mock time applied (TT-158): the base clock (the device clock, or the fixture clock in fixture runs)
/// while Mock time is off, else the chosen moment running on from when it was chosen. Read on each call, so a change in
/// Settings applies at once.
struct MockTimeClock: AppClock {
    let base: any AppClock
    var setting: @Sendable () -> MockTimeSetting? = { MockTime.stored }
    var real: @Sendable () -> Date = { Date() }

    var now: Date {
        setting().map { $0.now(real: real()) } ?? base.now
    }
}
