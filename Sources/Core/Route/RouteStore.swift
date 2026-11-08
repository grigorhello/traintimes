import Foundation

/// The last selected route and its direction, kept on device so the next launch opens it (TT-120).
/// Recent routes are stored separately (`RecentRoutes`, D48). Nothing is sent to a server (D5).
@MainActor
protocol RouteStoring {
    var route: Route? { get }
    func save(_ route: Route)
}

/// Stores the route as a dictionary of strings, so UI tests can set or clear it with a launch argument
/// (`-route.last "{fromId = OA; ...}"`, or `""` for a fresh install).
struct UserDefaultsRouteStore: RouteStoring {
    static let key = "route.last"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var route: Route? {
        (defaults.dictionary(forKey: Self.key) as? [String: String]).flatMap(Route.init(storedValues:))
    }

    func save(_ route: Route) {
        defaults.set(route.storedValues, forKey: Self.key)
    }
}

extension Route {
    /// The route as stored on device: fromId, fromName, toId, toName, and lineId, lineName, lineColor when it has a line.
    var storedValues: [String: String] {
        var values = ["fromId": from.id, "fromName": from.name, "toId": to.id, "toName": to.name]
        if let line {
            values["lineId"] = line.id
            values["lineName"] = line.name
            values["lineColor"] = line.colorHex
        }
        return values
    }

    init?(storedValues values: [String: String]) {
        guard let fromId = values["fromId"], let fromName = values["fromName"],
              let toId = values["toId"], let toName = values["toName"]
        else { return nil }
        let line = values["lineId"].flatMap { id in
            values["lineName"].map { Line(id: id, name: $0, colorHex: values["lineColor"]) }
        }
        self.init(from: Station(id: fromId, name: fromName), to: Station(id: toId, name: toName), line: line)
    }

    /// Same stations in the same direction. Each direction is its own recent route (D48).
    func isSameDirection(as other: Route) -> Bool {
        from.id == other.from.id && to.id == other.to.id
    }
}
