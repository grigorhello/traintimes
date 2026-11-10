import Foundation
import Observation

/// The routes the rider opened last, newest first, kept on device (D48). Each direction is its own entry, and opening a
/// route again moves it to the top. The station picker lists them under "Recent" on Schedule, leaving out the route on
/// screen, and their stations make up Your stations (D52). The last route is also stored on its own (`RouteStoring`) so a
/// relaunch opens it. Nothing is sent to a server (D5).
///
/// One instance is shared by Schedule, which records each route it shows, and the station picker.
@Observable @MainActor
final class RecentRoutes {
    /// The route on screen plus the three the picker lists.
    static let limit = 4
    /// How many the picker lists.
    static let shown = 3
    /// An array of route dictionaries (`Route.storedValues`), so UI tests can clear it with `-route.recent ""`.
    static let key = "route.recent"

    private(set) var routes: [Route]
    /// Nil keeps the list in memory only (previews, and tests that do not check recent routes).
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        let stored = defaults?.array(forKey: Self.key) as? [[String: String]] ?? []
        routes = Array(stored.compactMap(Route.init(storedValues:)).prefix(Self.limit))
    }

    /// Puts the route first, dropping its earlier entry and the oldest past the limit.
    func record(_ route: Route) {
        guard routes.first != route else { return }
        routes.removeAll { $0.isSameDirection(as: route) }
        routes.insert(route, at: 0)
        routes = Array(routes.prefix(Self.limit))
        defaults?.set(routes.map(\.storedValues), forKey: Self.key)
    }

    /// The routes the picker lists: up to three, newest first, without `current` in its direction.
    func routes(excluding current: Route?) -> [Route] {
        Array(routes.filter { route in current.map { !route.isSameDirection(as: $0) } ?? true }.prefix(Self.shown))
    }
}
