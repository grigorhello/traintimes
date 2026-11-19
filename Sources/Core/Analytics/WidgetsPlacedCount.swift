import Foundation

/// `widgets_placed` (TT-183): how many Next train and Departures widgets are on the Home Screen and how many Lock Screen
/// sizes of Next train are placed (`lock`, TT-184), read once each time the app comes to the front and sent only when the
/// counts differ from the last ones sent (kept on device). An install that never placed a widget sends nothing.
///
/// The counts are stored only while a tracker runs, so a Debug run never hides a change from a later TestFlight build.
@MainActor
struct WidgetsPlacedCount {
    static let key = "analytics.widgetsPlaced"

    /// Nil in previews and tests that do not check it: nothing is stored and nothing is sent.
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
    }

    func report(_ widgets: [PlacedWidget]) {
        guard let defaults, Analytics.tracker != nil else { return }
        let nextTrain = widgets.filter { $0.kind == .nextTrain }.count
        let departures = widgets.filter { $0.kind == .departures }.count
        let lock = widgets.filter(\.kind.isOnLockScreen).count
        let counts = "\(nextTrain),\(departures),\(lock)"
        guard counts != Self.withLock(defaults.string(forKey: Self.key) ?? "0,0") else { return }
        Analytics.track(.widgetsPlaced(nextTrain: nextTrain, departures: departures, lock: lock))
        defaults.set(counts, forKey: Self.key)
    }

    /// The stored counts with the Lock Screen's: a build before TT-184 stored the Home Screen's two only.
    private static func withLock(_ stored: String) -> String {
        stored.split(separator: ",").count == 2 ? stored + ",0" : stored
    }
}
