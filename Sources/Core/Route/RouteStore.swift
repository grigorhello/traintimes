import Foundation

/// The last selected route and its direction, kept on device so the next launch opens it (TT-120).
/// Favourites are stored separately (TT-122). Nothing is sent to a server (D5).
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
        guard let values = defaults.dictionary(forKey: Self.key) as? [String: String],
              let fromId = values["fromId"], let fromName = values["fromName"],
              let toId = values["toId"], let toName = values["toName"]
        else { return nil }
        let line = values["lineId"].flatMap { id in
            values["lineName"].map { Line(id: id, name: $0, colorHex: values["lineColor"]) }
        }
        return Route(from: Station(id: fromId, name: fromName), to: Station(id: toId, name: toName), line: line)
    }

    func save(_ route: Route) {
        var values = ["fromId": route.from.id, "fromName": route.from.name, "toId": route.to.id, "toName": route.to.name]
        if let line = route.line {
            values["lineId"] = line.id
            values["lineName"] = line.name
            values["lineColor"] = line.colorHex
        }
        defaults.set(values, forKey: Self.key)
    }
}
