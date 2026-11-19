import Foundation
@testable import TrainTimes

private final class BundleToken {}

/// A timetable both ways for the turn's tests (TT-235, D116): each direction's trips by the station it leaves from, with
/// gates a test closes on one direction's trips and on live status, and a timetable it can take away.
actor TurnScheduleRepository: ScheduleRepository {
    private let trips: [String: [Trip]]
    private var live: LiveSnapshot
    private var heldFrom: String?
    private var holdsLive = false
    private var hasTimetable = true
    private var parkedTrips: [CheckedContinuation<Void, Never>] = []
    private var parkedLive: [CheckedContinuation<Void, Never>] = []

    /// `trips`: the trains leaving each station, by its id. Another station has none.
    init(trips: [String: [Trip]], live: LiveSnapshot = .empty) {
        self.trips = trips
        self.live = live
    }

    /// The trips of routes leaving `station` stay unread until `releaseTrips()`.
    func holdTrips(from station: String) {
        heldFrom = station
    }

    func releaseTrips() {
        heldFrom = nil
        parkedTrips.forEach { $0.resume() }
        parkedTrips = []
    }

    /// Live status stays unread until `releaseLive(_:)`.
    func holdLive() {
        holdsLive = true
    }

    /// The held reads of live status get `live`, and later ones too.
    func releaseLive(_ live: LiveSnapshot) {
        self.live = live
        holdsLive = false
        parkedLive.forEach { $0.resume() }
        parkedLive = []
    }

    /// From here on there is no timetable to read.
    func removeTimetable() {
        hasTimetable = false
    }

    /// Reads waiting at a closed gate.
    var tripsWaiting: Int { parkedTrips.count }
    var liveWaiting: Int { parkedLive.count }

    func trips(for route: Route, on day: ServiceDay) async throws -> [Trip] {
        if heldFrom == route.from.id {
            await withCheckedContinuation { parkedTrips.append($0) }
        }
        guard hasTimetable else { throw URLError(.notConnectedToInternet) }
        return trips[route.from.id] ?? []
    }

    func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot {
        if holdsLive {
            await withCheckedContinuation { parkedLive.append($0) }
        }
        return live
    }

    func lineNotices(for line: Line) async throws -> [LineNotice] { [] }
}

/// The turn's test values (TT-235, D116): the fixture route, Oakville to Union on Thu Nov 5 at 7:21 AM, with its four
/// trains, and three trains the other way.
enum TurnFixtures {
    struct Timetable: Sendable {
        let route: Route
        let reversed: Route
        let now: Date
        let day: ServiceDay
        /// Oakville to Union: the fixture's trains.
        let trips: [Trip]
        /// Union to Oakville: 7:40, 8:10 and 8:40 AM.
        let reverseTrips: [Trip]

        /// Both directions, by the station each leaves from.
        func repository(live: LiveSnapshot = .empty) -> TurnScheduleRepository {
            TurnScheduleRepository(trips: [route.from.id: trips, route.to.id: reverseTrips], live: live)
        }
    }

    static func timetable() async throws -> Timetable {
        let fixture = try FixtureScheduleRepository(bundle: Bundle(for: BundleToken.self))
        let day = fixture.serviceDay
        let route = fixture.route
        let reverseTrips = [(7, 40), (8, 10), (8, 40)].enumerated().map { index, time in
            let departure = day.date(hour: time.0, minute: time.1)
            return Trip(
                key: TripKey(serviceDay: day, tripId: "LW-R\(index)"), scheduledDeparture: departure,
                scheduledArrival: departure.addingTimeInterval(40 * 60), platform: .pending, tags: []
            )
        }
        return Timetable(
            route: route, reversed: Route(from: route.to, to: route.from, line: route.line), now: fixture.now, day: day,
            trips: try await fixture.trips(for: route, on: day), reverseTrips: reverseTrips
        )
    }
}
