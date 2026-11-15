@testable import TrainTimes

/// Records what the app tracks (TT-208): install it with `RecordingAnalytics.install()` and the test's tear-down puts the
/// silent default back.
@MainActor
final class RecordingAnalytics: AnalyticsTracking {
    private(set) var events: [AnalyticsEvent] = []
    private(set) var screens: [AnalyticsScreen] = []

    var names: [String] { events.map(\.name) }

    func track(_ event: AnalyticsEvent) { events.append(event) }
    func screen(_ screen: AnalyticsScreen) { screens.append(screen) }

    static func install() -> RecordingAnalytics {
        let recorder = RecordingAnalytics()
        Analytics.tracker = recorder
        return recorder
    }
}
