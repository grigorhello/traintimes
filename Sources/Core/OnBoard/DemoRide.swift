import Foundation

/// Settings › Testing › Demo trains › Ride (TT-172, D61): the 5:13 PM Lakeshore West train from Union to Clarkson, played
/// from 5:32 to 5:43 PM today, so the ride's moments (riding, at a station, your stop next, arriving, at your stop) can be
/// checked on the simulator with no train. It runs on a ride engine of its own with a clock of its own, six times as fast,
/// and a location track that keeps to the timetable; it keeps nothing on device and leaves the app's engine alone.
enum DemoRide {
    static let tripId = "DEMO-LW-1713"
    static let line = Line(id: "LW", name: "Lakeshore West", colorHex: nil)
    /// The demo clock starts here, seconds into the service day as GTFS counts them (5:32 PM).
    static let startSeconds = 17 * 3600 + 32 * 60
    /// The demo clock runs this many times as fast as the real one: the 11 minutes take under 2.
    static let speed = 6.0
    /// How long the train stands at each station between the two ends.
    static let dwell: TimeInterval = 40

    private struct Call {
        let station: Station
        let place: GeoPoint
        /// Arrival, in minutes after 5:00 PM.
        let minute: Int
    }

    private static let calls = [
        Call(station: Station(id: "UN", name: "Union Station GO"), place: GeoPoint(latitude: 43.645195, longitude: -79.380600), minute: 13),
        Call(station: Station(id: "EX", name: "Exhibition GO"), place: GeoPoint(latitude: 43.635549, longitude: -79.418927), minute: 19),
        Call(station: Station(id: "MI", name: "Mimico GO"), place: GeoPoint(latitude: 43.616411, longitude: -79.497762), minute: 25),
        Call(station: Station(id: "LO", name: "Long Branch GO"), place: GeoPoint(latitude: 43.591317, longitude: -79.546149), minute: 30),
        Call(station: Station(id: "PO", name: "Port Credit GO"), place: GeoPoint(latitude: 43.555999, longitude: -79.586881), minute: 36),
        Call(station: Station(id: "CL", name: "Clarkson GO"), place: GeoPoint(latitude: 43.513127, longitude: -79.633206), minute: 43),
    ]

    /// A bend between each pair of stations, so the track is not a straight line.
    private static let bends = [
        GeoPoint(latitude: 43.641500, longitude: -79.399000),
        GeoPoint(latitude: 43.627500, longitude: -79.458000),
        GeoPoint(latitude: 43.604500, longitude: -79.522500),
        GeoPoint(latitude: 43.574000, longitude: -79.567000),
        GeoPoint(latitude: 43.535000, longitude: -79.611000),
    ]

    /// Union to Clarkson on Lakeshore West: the sheet's header and the ride's two ends.
    static var route: Route {
        Route(from: calls[0].station, to: calls[calls.count - 1].station, line: line)
    }

    static func ride(on day: ServiceDay) -> Ride {
        Ride(trip: TripKey(serviceDay: day, tripId: tripId), from: route.from.id, to: route.to.id)
    }

    /// The six stops with their times on `day`, and the track through them.
    static func plan(on day: ServiceDay) -> RidePlan {
        let last = calls.count - 1
        let stops = calls.enumerated().map { index, call -> RidePlan.Stop in
            let arrival = day.gtfsTime(17 * 3600 + call.minute * 60)
            let stands = index == 0 || index == last ? 0 : dwell
            return RidePlan.Stop(station: call.station, arrival: arrival, departure: arrival.addingTimeInterval(stands))
        }
        var points: [GeoPoint] = []
        for (index, call) in calls.enumerated() {
            points.append(call.place)
            if index < bends.count { points.append(bends[index]) }
        }
        let shape = TrackShape(points: points)
        return RidePlan(stops: stops, track: RidePlan.Track(shape: shape, stopDistances: shape.distances(of: calls.map(\.place))))
    }

    /// Where the demo train is at `time`, in metres along its track: standing at each station from its arrival to its
    /// departure, and at an even speed between them.
    static func along(at time: Date, plan: RidePlan) -> Double {
        guard let distances = plan.track?.stopDistances, let lastDistance = distances.last else { return 0 }
        let stops = plan.stops
        for index in stops.indices {
            if time < stops[index].arrival {
                guard index > 0 else { return distances[0] }
                let leaves = stops[index - 1].departure
                let span = stops[index].arrival.timeIntervalSince(leaves)
                let fraction = span > 0 ? min(max(time.timeIntervalSince(leaves) / span, 0), 1) : 1
                return distances[index - 1] + (distances[index] - distances[index - 1]) * fraction
            }
            if time <= stops[index].departure { return distances[index] }
        }
        return lastDistance
    }

    /// The demo's engine on `day`, read against `clock`. `tickInterval` nil runs no timer and sends one fix, at the start
    /// (tests and snapshots).
    @MainActor
    static func engine(on day: ServiceDay, clock: any AppClock, tickInterval: Duration? = .seconds(1)) -> RideEngine {
        let ridePlan = plan(on: day)
        return RideEngine(
            data: DemoRideData(plan: ridePlan),
            location: DemoLocation(plan: ridePlan, clock: clock, interval: tickInterval),
            clock: clock,
            defaults: nil,
            tickInterval: tickInterval
        )
    }

    /// The demo as Settings › Testing plays it: today, from 5:32 PM, six times as fast.
    @MainActor
    static func session(startingAt realStart: Date = Date()) -> (engine: RideEngine, ride: Ride) {
        let day = ServiceDay(calendarDayContaining: realStart)
        let clock = DemoRideClock(start: day.gtfsTime(startSeconds), realStart: realStart, speed: speed)
        return (engine(on: day, clock: clock), ride(on: day))
    }
}

/// The demo ride's clock: 5:32 PM when the demo starts, running `speed` times as fast as the real clock from then.
struct DemoRideClock: AppClock {
    let start: Date
    let realStart: Date
    let speed: Double

    var now: Date {
        start.addingTimeInterval(max(0, Date().timeIntervalSince(realStart)) * speed)
    }
}

/// The schedule side of the demo ride: its one plan, on time.
struct DemoRideData: RideDataProviding {
    let plan: RidePlan

    func ridePlan(for ride: Ride) async throws -> RidePlan? {
        ride.tripId == DemoRide.tripId ? plan : nil
    }

    func rideStatus(for ride: Ride) async -> RideStatus { .none }
}

/// The demo ride's location: a fix on the track where the demo train is by its clock, at once and then each `interval`.
/// Allowed from the start, so the demo never shows the iOS prompt.
@MainActor
final class DemoLocation: LocationProviding {
    private let plan: RidePlan
    private let clock: any AppClock
    private let interval: Duration?
    private var updates: Task<Void, Never>?

    init(plan: RidePlan, clock: any AppClock, interval: Duration?) {
        self.plan = plan
        self.clock = clock
        self.interval = interval
    }

    var isAuthorized: Bool { true }
    var canAsk: Bool { false }

    func requestWhenInUse() async -> Bool { true }

    func startUpdates(_ onFix: @escaping @MainActor @Sendable (LocationFix) -> Void) {
        stopUpdates()
        onFix(fix())
        guard let interval else { return }
        updates = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let fix = self?.fix() else { return }
                onFix(fix)
            }
        }
    }

    func stopUpdates() {
        updates?.cancel()
        updates = nil
    }

    private func fix() -> LocationFix {
        let point = plan.track?.shape.point(at: DemoRide.along(at: clock.now, plan: plan)) ?? GeoPoint(latitude: 0, longitude: 0)
        return LocationFix(coordinate: point, horizontalAccuracy: 5)
    }
}
