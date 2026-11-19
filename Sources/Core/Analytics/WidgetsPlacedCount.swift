import Foundation

/// `widgets_placed` (TT-183): how many Next train and Departures widgets are on the Home Screen, read once each time the
/// app comes to the front and sent only when the counts differ from the last ones sent (kept on device). An install that
/// never placed a widget sends nothing.
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
        let counts = "\(nextTrain),\(departures)"
        guard counts != defaults.string(forKey: Self.key) ?? "0,0" else { return }
        Analytics.track(.widgetsPlaced(nextTrain: nextTrain, departures: departures))
        defaults.set(counts, forKey: Self.key)
    }
}
