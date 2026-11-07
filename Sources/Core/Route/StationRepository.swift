import Foundation

/// The stations a route can join: fixtures in M1, GTFS stops in TT-130. Station search (TT-121) reads the same list.
protocol StationRepository: Sendable {
    /// Every station, alphabetically.
    func stations() async throws -> [Station]
    /// The route between two stations, with the line that serves both; `line` is nil when no line connects them,
    /// and the route still saves (Schedule then shows "No direct connection", TT-115).
    func route(from: Station, to: Station) async throws -> Route
}
