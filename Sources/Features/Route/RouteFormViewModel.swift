import Foundation
import Observation

/// The model behind the inline station picker (TT-161, D54): From and To, swap, and "Show trains" once both are set and
/// different. The first screen on first launch uses it, and Schedule makes one each time the rider taps a station in its
/// route card. Tapping a station row makes it the search field and unfolds suggestions under the card: Recent routes
/// (Schedule only, before typing), Your stations, then All stations, filtered by `query`. Once the other field holds a
/// station, All stations gives way to a section per line serving it and then Other stations (TT-200, D83).
@Observable @MainActor
final class RouteFormViewModel {
    enum Field: String {
        case from, to
    }

    /// One station row of the suggestions.
    struct StationRow: Identifiable, Equatable {
        let station: Station
        /// Line context in `footnote` ("Lakeshore West", "All lines"), plus "Same as To" or "Same as From" when greyed.
        let detail: String
        /// In one of the recent routes: listed under Your stations, with a clock.
        let isRecent: Bool
        /// The other field already holds this station, so the row is greyed and cannot be picked.
        let isDisabled: Bool

        var id: String { station.id }
    }

    /// The stations on one line of the other field's station, from Union outward (TT-200, D83).
    struct LineSection: Identifiable, Equatable {
        let line: Line
        let rows: [StationRow]

        var id: String { line.id }
    }

    /// Suggested first when choosing To (the GTFS stop id of Union Station GO).
    static let unionStationId = "UN"

    private(set) var from: Station?
    private(set) var to: Station?
    private(set) var stations: [Station] = []
    private(set) var isPickingStation = false
    /// The field the picker picks for. Kept after the picker folds, so the card does not change on the way out.
    private(set) var pickingField: Field = .from
    /// The typed search text; cleared each time the picker opens, moves on to another field or folds.
    var query = ""

    /// The routes opened last, shared with Schedule, which records them (D48).
    let recents: RecentRoutes

    private let repository: any StationRepository
    /// The route on screen when the picker opens from Schedule, left out of Recent; nil on first use.
    private let current: Route?

    /// `route` is the route on screen when the picker opens from the Schedule route card; nil on first use. `recents` are
    /// the routes opened last: the Recent group, and their stations make up Your stations.
    init(route: Route?, repository: any StationRepository, recents: RecentRoutes = RecentRoutes(defaults: nil)) {
        from = route?.from
        to = route?.to
        current = route
        self.repository = repository
        self.recents = recents
    }

    private var recentStationIds: Set<String> {
        Set(recents.routes.flatMap { [$0.from.id, $0.to.id] })
    }

    /// Schedule applies a pick at once, over the route on screen; first use waits for "Show trains".
    var appliesAtOnce: Bool { current != nil }

    /// Identical stations are rejected inline.
    var isSameStation: Bool { from != nil && from?.id == to?.id }
    var canShowTrains: Bool { from != nil && to != nil && !isSameStation }
    var canSwap: Bool { from != nil || to != nil }

    /// Stations in the recent routes, alphabetically, with a clock.
    var yourStations: [StationRow] {
        rows(stations.filter { recentStationIds.contains($0.id) })
    }

    /// The other field's station with its lines from the station list (a saved route's station carries none); nil while
    /// that field is empty.
    private var otherStation: Station? {
        guard let other = pickingField == .from ? to : from else { return nil }
        return stations.first { $0.id == other.id }
    }

    /// The lines of the other field's station; empty while it is empty or its lines are unknown, which keeps today's list.
    private var sharedLines: [String] {
        otherStation?.lines ?? []
    }

    /// A section per line serving the other field's station, in GO's line order, each from Union outward, without that
    /// station itself; typing filters them like the rest, so same-line matches come first. Empty with no station chosen.
    var lineSections: [LineSection] {
        guard let other = otherStation else { return [] }
        let hub = stations.first { $0.id == Self.unionStationId }?.place
        return GOLineColor.ordered(other.lines).compactMap { name in
            let list = stations.filter { $0.id != other.id && $0.lines.contains(name) }
            let found = rows(Self.fromUnionOutward(list, hub: hub))
            return found.isEmpty ? nil : LineSection(line: GOLineColor.line(named: name), rows: found)
        }
    }

    /// Union first, then by distance from Union when every station has a place (the GTFS feed), else alphabetically.
    private static func fromUnionOutward(_ list: [Station], hub: GeoPoint?) -> [Station] {
        let union = list.filter { $0.id == unionStationId }
        let rest = list.filter { $0.id != unionStationId }
        guard let hub, rest.allSatisfy({ $0.place != nil }) else { return union + rest }
        let distance = { (station: Station) in station.place.map { TrackShape.distance(hub, $0) } ?? 0 }
        return union + rest.sorted { distance($0) < distance($1) }
    }

    /// Every station alphabetically; when choosing To, Union Station GO comes first unless it is the From station. Once
    /// the other field's station has line sections, only the stations on none of its lines (Other stations).
    var allStations: [StationRow] {
        let shared = Set(sharedLines)
        if !shared.isEmpty {
            return rows(stations.filter { shared.isDisjoint(with: $0.lines) })
        }
        var list = stations
        if pickingField == .to, from?.id != Self.unionStationId,
           let index = list.firstIndex(where: { $0.id == Self.unionStationId }) {
            list.insert(list.remove(at: index), at: 0)
        }
        return rows(list)
    }

    /// The station the active field holds, shown selected when the picker opens so typing replaces it; nil while empty.
    var pickingStationName: String? {
        (pickingField == .from ? from : to)?.name
    }

    /// The Recent group: up to three routes, newest first, without the one on screen. Schedule only, and only before the
    /// rider types.
    var suggestedRoutes: [Route] {
        appliesAtOnce && trimmedQuery.isEmpty ? recents.routes(excluding: current) : []
    }

    /// Nothing in the picker matches the typed text.
    var hasNoMatch: Bool {
        !stations.isEmpty && suggestedRoutes.isEmpty && yourStations.isEmpty && lineSections.isEmpty && allStations.isEmpty
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

    /// Cancel: the X, a tap on the scrim or a swipe down. The stations stay as they were.
    func closeStations() {
        isPickingStation = false
        query = ""
    }

    /// Picking From while To is empty moves the picker straight on to To, so the first route takes two picks and one tap.
    /// The other field's station cannot be picked. Returns true when the form applies picks at once (Schedule) and this
    /// pick completed the route, so the caller shows `route()` now.
    @discardableResult
    func pick(_ station: Station) -> Bool {
        guard !isTaken(station) else { return false }
        query = ""
        switch pickingField {
        case .from:
            from = station
            if to == nil {
                pickingField = .to
                return false
            }
        case .to:
            to = station
        }
        isPickingStation = false
        return appliesAtOnce && canShowTrains
    }

    /// A Recent row applies both of its stations at once (Schedule).
    func choose(_ route: Route) {
        from = route.from
        to = route.to
        closeStations()
    }

    /// The Return key picks the first station the typed text finds.
    @discardableResult
    func pickFirstMatch() -> Bool {
        guard !trimmedQuery.isEmpty,
              let row = (yourStations + lineSections.flatMap(\.rows) + allStations).first(where: { !$0.isDisabled })
        else { return false }
        return pick(row.station)
    }

    /// Swap is explicit, never automatic.
    func swap() {
        (from, to) = (to, from)
    }

    /// "Oakville to Union", read for a Recent row.
    func title(_ route: Route) -> String {
        String(format: String(localized: "schedule.route_title"), route.from.name, route.to.name)
    }

    /// The route "Show trains" opens, with its line from the repository; nil until the form is valid.
    func route() async -> Route? {
        guard canShowTrains, let from, let to else { return nil }
        return (try? await repository.route(from: from, to: to)) ?? Route(from: from, to: to, line: nil)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    /// The name, or the name from any word on, starts with `prefix`: "oak" and "uni" find Oakville GO and Union Station GO,
    /// "st" finds Union Station GO too.
    private static func matches(_ name: String, prefix: String) -> Bool {
        var start = name.startIndex
        while start < name.endIndex {
            let rest = name[start...]
            if rest.range(of: prefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil { return true }
            guard let separator = rest.firstIndex(where: { $0 == " " || $0 == "-" }) else { return false }
            start = name.index(after: separator)
        }
        return false
    }

    /// The station already chosen for the other field.
    private func isTaken(_ station: Station) -> Bool {
        station.id == (pickingField == .from ? to : from)?.id
    }

    /// The station the active field holds now; it is not listed, since picking it again would change nothing.
    private var ownStationId: String? {
        (pickingField == .from ? from : to)?.id
    }

    /// Filters by the typed text (a word prefix, case and accent insensitive) and builds each row's footnote.
    private func rows(_ list: [Station]) -> [StationRow] {
        let text = trimmedQuery
        let allLines = Set(stations.flatMap(\.lines))
        let sameAsKey: String.LocalizationValue = pickingField == .from ? "stations.same_as_to" : "stations.same_as_from"
        let sameAs = String(localized: sameAsKey)
        return list
            .filter { $0.id != ownStationId }
            .filter { text.isEmpty || Self.matches($0.name, prefix: text) }
            .map { station in
                let lines = allLines.count > 1 && Set(station.lines) == allLines
                    ? String(localized: "stations.all_lines")
                    : station.lines.joined(separator: ", ")
                let isDisabled = isTaken(station)
                return StationRow(
                    station: station,
                    detail: isDisabled ? String(format: sameAs, lines) : lines,
                    isRecent: recentStationIds.contains(station.id),
                    isDisabled: isDisabled
                )
            }
    }
}
