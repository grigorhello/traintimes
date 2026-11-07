import Foundation
import Observation

/// The route form (TT-120): From and To, swap, and "Show trains" once both are set and different.
/// It is the first screen on first launch and the route sheet from the Schedule header.
/// Station search (TT-121) picks for one field at a time: Your stations, then All stations, filtered by `query`.
@Observable @MainActor
final class RouteFormViewModel {
    enum Field: String {
        case from, to
    }

    /// One row of the station search.
    struct StationRow: Identifiable, Equatable {
        let station: Station
        /// Line context in `footnote` ("Lakeshore West", "All lines"), plus "Same as To" or "Same as From" when greyed.
        let detail: String
        let isFavourite: Bool
        /// The other field already holds this station, so the row is greyed and cannot be picked.
        let isDisabled: Bool

        var id: String { station.id }
    }

    /// Suggested first when choosing To (the GTFS stop id of Union Station GO).
    static let unionStationId = "UN"

    private(set) var from: Station?
    private(set) var to: Station?
    private(set) var stations: [Station] = []
    private(set) var isPickingStation = false
    /// The field the station list picks for. Kept after the list closes, so its title does not change on the way out.
    private(set) var pickingField: Field = .from
    /// The station search text; cleared each time the search opens or moves on to another field.
    var query = ""

    private let repository: any StationRepository
    private let favouriteStationIds: Set<String>

    /// `route` prefills the form when it opens from the Schedule header; nil on first use. `favourites` are the rider's
    /// favourite routes (TT-122); their stations make up Your stations.
    init(route: Route?, repository: any StationRepository, favourites: [Route] = []) {
        from = route?.from
        to = route?.to
        self.repository = repository
        favouriteStationIds = Set(favourites.flatMap { [$0.from.id, $0.to.id] })
    }

    /// Identical stations are rejected inline.
    var isSameStation: Bool { from != nil && from?.id == to?.id }
    var canShowTrains: Bool { from != nil && to != nil && !isSameStation }
    var canSwap: Bool { from != nil || to != nil }

    /// Stations in the rider's favourite routes, alphabetically and starred.
    var yourStations: [StationRow] {
        rows(stations.filter { favouriteStationIds.contains($0.id) })
    }

    /// Every station alphabetically; when choosing To, Union Station GO comes first unless it is the From station.
    var allStations: [StationRow] {
        var list = stations
        if pickingField == .to, from?.id != Self.unionStationId,
           let index = list.firstIndex(where: { $0.id == Self.unionStationId }) {
            list.insert(list.remove(at: index), at: 0)
        }
        return rows(list)
    }

    func loadStations() async {
        guard stations.isEmpty else { return }
        stations = (try? await repository.stations()) ?? []
    }

    func open(_ field: Field) {
        pickingField = field
        query = ""
        isPickingStation = true
    }

    func closeStations() {
        isPickingStation = false
    }

    /// Picking From while To is empty moves the list straight on to To, so the first route takes two picks and one tap.
    /// The other field's station cannot be picked.
    func pick(_ station: Station) {
        guard !isTaken(station) else { return }
        query = ""
        switch pickingField {
        case .from:
            from = station
            if to == nil {
                pickingField = .to
            } else {
                isPickingStation = false
            }
        case .to:
            to = station
            isPickingStation = false
        }
    }

    /// Swap is explicit, never automatic.
    func swap() {
        (from, to) = (to, from)
    }

    /// The route "Show trains" opens, with its line from the repository; nil until the form is valid.
    func route() async -> Route? {
        guard canShowTrains, let from, let to else { return nil }
        return (try? await repository.route(from: from, to: to)) ?? Route(from: from, to: to, line: nil)
    }

    /// The station already chosen for the other field.
    private func isTaken(_ station: Station) -> Bool {
        station.id == (pickingField == .from ? to : from)?.id
    }

    /// Filters by `query` (case and accent insensitive, anywhere in the name) and builds each row's footnote.
    private func rows(_ list: [Station]) -> [StationRow] {
        let text = query.trimmingCharacters(in: .whitespaces)
        let allLines = Set(stations.flatMap(\.lines))
        let sameAsKey: String.LocalizationValue = pickingField == .from ? "stations.same_as_to" : "stations.same_as_from"
        let sameAs = String(localized: sameAsKey)
        return list
            .filter { text.isEmpty || $0.name.localizedStandardContains(text) }
            .map { station in
                let lines = allLines.count > 1 && Set(station.lines) == allLines
                    ? String(localized: "stations.all_lines")
                    : station.lines.joined(separator: ", ")
                let isDisabled = isTaken(station)
                return StationRow(
                    station: station,
                    detail: isDisabled ? String(format: sameAs, lines) : lines,
                    isFavourite: favouriteStationIds.contains(station.id),
                    isDisabled: isDisabled
                )
            }
    }
}
