import Foundation

/// The clock a view model reads "now" from, injected so tests and fixtures can fix the time.
protocol AppClock: Sendable {
    var now: Date { get }
}

/// The device clock.
struct SystemClock: AppClock {
    var now: Date { Date() }
}

/// A clock stopped at one moment: the fixture clock in M1 (D20) and in tests.
struct FixedClock: AppClock {
    let now: Date
}
