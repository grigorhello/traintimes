import Foundation

/// `widgets_placed` (TT-183): how many Next train and Departures widgets are on the Home Screen, how many Lock Screen
/// sizes of Next train are placed (`lock`, TT-184) and how many of them all show My trains and A route (TT-257), read once each time the app comes to the front and sent only when the
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
        let myTrains = widgets.filter { $0.mode == .myTrains }.count
        let route = widgets.count - myTrains
        let counts = "\(nextTrain),\(departures),\(lock),\(myTrains),\(route)"
        guard counts != Self.padded(defaults.string(forKey: Self.key) ?? "0") else { return }
        Analytics.track(.widgetsPlaced(nextTrain: nextTrain, departures: departures, lock: lock, myTrains: myTrains, route: route))
        defaults.set(counts, forKey: Self.key)
    }

    /// The stored counts as five: a build before TT-184 stored the Home Screen's two, one before TT-257 three; a count it
    /// did not keep reads 0, so an install that never placed a widget still sends nothing.
    private static func padded(_ stored: String) -> String {
        let parts = stored.split(separator: ",").map(String.init)
        return (parts + Array(repeating: "0", count: max(0, 5 - parts.count))).joined(separator: ",")
    }
}
