import Foundation
import Observation

/// The first launch (TT-206, D94): the welcome, step 1 (your line), step 2 (your station), then Schedule on that route.
/// "Choose your line", a line and a station make three taps; a tile on the welcome's picture picks its line at once, so two.
/// The lines and their stations ship in the app (`GONetwork`), so nothing here waits for the timetable, whose download
/// starts as the welcome appears. "Search stations", and a tap on a station row of step 2's route card, open the route form
/// of TT-120 instead (the keyboard path).
@Observable @MainActor
final class WelcomeViewModel {
    enum Step: Equatable {
        case welcome
        /// Step 1 of 2: the seven lines.
        case lines
        /// Step 2 of 2: the line's stations. `fromMap` when its tile was tapped on the welcome's picture (the list skipped).
        case station(lineId: String, fromMap: Bool)
        /// The route form with its picker (`routeForm`).
        case search
    }

    private(set) var step: Step = .welcome
    /// The route form behind "Search stations", made when it opens.
    private(set) var routeForm: RouteFormViewModel?
    /// Where each line's row on step 1 puts its tile, and where step 2 seats the chosen one, as the view measured them: the
    /// tiles fly to them. Kept here, like the timeline's measured cards (TT-113), so a snapshot draws them in place.
    var rowFrames: [String: CGRect] = [:]
    var seatFrame: CGRect?

    private let stations: any StationRepository
    private let clock: any AppClock
    private let recents: RecentRoutes

    init(stations: any StationRepository, clock: any AppClock, recents: RecentRoutes = RecentRoutes(defaults: nil)) {
        self.stations = stations
        self.clock = clock
        self.recents = recents
    }

    var lines: [GONetwork.LineStations] { GONetwork.lines }

    /// The line step 2 shows; nil on the other steps.
    var chosenLine: GONetwork.LineStations? {
        guard case .station(let id, _) = step else { return nil }
        return GONetwork.line(id)
    }

    /// Step 1 or 2 of 2, for the progress mark; nil on the welcome and the route form.
    var stepNumber: Int? {
        switch step {
        case .lines: 1
        case .station: 2
        case .welcome, .search: nil
        }
    }

    /// Before noon in Toronto the route runs from your station to Union, from noon on from Union to your station.
    var unionIsFirst: Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = goTimeZone
        return calendar.component(.hour, from: clock.now) >= 12
    }

    /// The timetable's download gets a head start while the rider reads the welcome (the feed store downloads on first use).
    func prepareTimetable() async {
        _ = try? await stations.stations()
    }

    /// "Choose your line".
    func chooseYourLine() {
        step = .lines
    }

    /// A line row, or its tile on the welcome's picture.
    func pick(lineId: String, fromMap: Bool = false) {
        guard GONetwork.line(lineId) != nil else { return }
        step = .station(lineId: lineId, fromMap: fromMap)
    }

    /// The X on step 2's route card: back to the lines.
    func backToLines() {
        step = .lines
    }

    /// The name above step 1's question: back to the welcome.
    func backToWelcome() {
        step = .welcome
    }

    /// "Search stations" on step 1: the route form as on first use before TT-206.
    func searchStations() {
        routeForm = RouteFormViewModel(route: nil, repository: stations, recents: recents)
        step = .search
    }

    /// A station row of step 2's route card: the route form with Union where step 2 had it, searching the tapped row.
    func search(_ field: RouteFormViewModel.Field) {
        let form = RouteFormViewModel(route: nil, repository: stations, recents: recents)
        form.preset(from: unionIsFirst ? GONetwork.union : nil, to: unionIsFirst ? nil : GONetwork.union)
        form.open(field)
        routeForm = form
        step = .search
    }

    /// The route a station of step 2 opens, on the chosen line, in the before-noon direction.
    func route(to station: Station) -> Route? {
        guard let line = chosenLine?.line else { return nil }
        return unionIsFirst
            ? Route(from: GONetwork.union, to: station, line: line)
            : Route(from: station, to: GONetwork.union, line: line)
    }
}
