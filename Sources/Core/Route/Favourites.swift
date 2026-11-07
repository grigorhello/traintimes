import Foundation
import Observation

/// Up to three favourite routes, kept on device (TT-122). Each direction is its own favourite, and the list never
/// replaces one on its own: when it is full, adding fails and the rider removes one first. The last selected route is
/// stored separately (`RouteStoring`). Nothing is sent to a server (D5).
///
/// One instance is shared by the Schedule star and the route form, so a change in either shows in both.
@Observable @MainActor
final class Favourites {
    static let limit = 3
    /// An array of route dictionaries (`Route.storedValues`), so UI tests can clear it with `-route.favourites ""`.
    static let key = "route.favourites"

    private(set) var routes: [Route]
    /// Nil keeps the list in memory only (previews, and tests that do not check favourites).
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        let stored = defaults?.array(forKey: Self.key) as? [[String: String]] ?? []
        routes = Array(stored.compactMap(Route.init(storedValues:)).prefix(Self.limit))
    }

    var isFull: Bool { routes.count >= Self.limit }

    func contains(_ route: Route) -> Bool {
        routes.contains { $0.isSameDirection(as: route) }
    }

    /// Adds the route at the end. Returns false, and changes nothing, when the list is already full.
    @discardableResult
    func add(_ route: Route) -> Bool {
        guard !contains(route) else { return true }
        guard !isFull else { return false }
        routes.append(route)
        save()
        return true
    }

    func remove(_ route: Route) {
        routes.removeAll { $0.isSameDirection(as: route) }
        save()
    }

    private func save() {
        defaults?.set(routes.map(\.storedValues), forKey: Self.key)
    }
}
