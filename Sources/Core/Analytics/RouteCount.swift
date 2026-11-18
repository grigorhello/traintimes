import Foundation

/// `route_set` once per install at least (TT-217): a route saved before the app sent analytics (an install from before
/// TT-208's build) never sent one, so the install never showed as activated. At launch such a route is counted once,
/// with `restored`; any route sent from the app marks the install too, so neither path counts it twice.
///
/// The mark is written only while a tracker runs, so a Debug run never stops a later TestFlight build from counting.
@MainActor
struct RouteCount {
    static let key = "analytics.routeCounted"

    /// Nil in previews and tests that do not check it: nothing is marked and nothing is counted at launch.
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
    }

    /// At launch, with the route saved on device.
    func launched(with route: Route?) {
        guard let route, let defaults, Analytics.tracker != nil, !defaults.bool(forKey: Self.key) else { return }
        Analytics.track(.routeSet(route, isFirst: true, restored: true))
        defaults.set(true, forKey: Self.key)
    }

    /// A route shown on Schedule from the app (first use, the station picker, Recent).
    func set(_ route: Route, isFirst: Bool) {
        Analytics.track(.routeSet(route, isFirst: isFirst))
        if Analytics.tracker != nil { defaults?.set(true, forKey: Self.key) }
    }
}
