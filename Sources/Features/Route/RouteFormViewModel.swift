import Foundation
import Observation

/// The route form (TT-120): From and To, swap, and "Show trains" once both are set and different.
/// It is the first screen on first launch and the route sheet from the Schedule header.
@Observable @MainActor
final class RouteFormViewModel {
    enum Field: String {
        case from, to
    }

    private(set) var from: Station?
    private(set) var to: Station?
    private(set) var stations: [Station] = []
    private(set) var isPickingStation = false
    /// The field the station list picks for. Kept after the list closes, so its title does not change on the way out.
    private(set) var pickingField: Field = .from

    private let repository: any StationRepository

    /// `route` prefills the form when it opens from the Schedule header; nil on first use.
    init(route: Route?, repository: any StationRepository) {
        from = route?.from
        to = route?.to
        self.repository = repository
    }

    /// Identical stations are rejected inline.
    var isSameStation: Bool { from != nil && from == to }
    var canShowTrains: Bool { from != nil && to != nil && !isSameStation }
    var canSwap: Bool { from != nil || to != nil }

    func loadStations() async {
        guard stations.isEmpty else { return }
        stations = (try? await repository.stations()) ?? []
    }

    func open(_ field: Field) {
        pickingField = field
        isPickingStation = true
    }

    func closeStations() {
        isPickingStation = false
    }

    /// Picking From while To is empty moves the list straight on to To, so the first route takes two picks and one tap.
    func pick(_ station: Station) {
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
}
