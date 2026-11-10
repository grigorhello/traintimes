import Foundation

/// The stations a route can join: the GTFS feed's in the app (TT-130), fixtures in previews and tests. The station picker
/// (TT-121, D53) reads the same list.
protocol StationRepository: Sendable {
    /// Every station, alphabetically.
    func stations() async throws -> [Station]
    /// The route between two stations, with the line that serves both; `line` is nil when no line connects them,
    /// and the route still saves (Schedule then shows "No direct connection", TT-115).
    func route(from: Station, to: Station) async throws -> Route
}
