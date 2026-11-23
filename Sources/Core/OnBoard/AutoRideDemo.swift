import Foundation

/// Settings › Testing › Demo trains › Depart › Automatic ride (TT-242, D120): a watch on the demo departure's train, on the
/// demo's clock, with a phone that leaves Union with the train (Boards), stays there (Stays) or leaves with no train
/// positions (No feed). It holds nothing on the server (the demo has no server card) and keeps nothing on device; a ride it
/// starts is the demo departure's hand-off (`OnBoard.handOffDemo(source: .auto)`).
enum AutoRideDemo {
    /// The watch looks every 1.5 s, 15 s on the demo's 10x clock, as the app's watch does on the real one.
    static let lookInterval: Duration = .milliseconds(1500)
    /// A fix every 200 ms, 2 s on the demo's clock.
    static let fixInterval: Duration = .milliseconds(200)

    /// The demo train as the watch sees it: the demo ride's stops and track, 3 min late, as the demo departure runs from
    /// 5:04 PM (it leaves Union at 5:16).
    static func plan(on day: ServiceDay) -> RidePlan {
        let plan = DemoRide.plan(on: day)
        let delay = TimeInterval(DemoDeparture.delayMinutes * 60)
        let stops = plan.stops.map {
            RidePlan.Stop(station: $0.station, arrival: $0.arrival.addingTimeInterval(delay), departure: $0.departure.addingTimeInterval(delay))
        }
        return RidePlan(stops: stops, track: plan.track)
    }

    /// The demo watch for `mode` on `session`'s clock. `start` hands the demo departure over to the demo ride, `rideRuns`
    /// says whether a ride (the demo's) runs, `isDeclined` whether the demo train was declined.
    @MainActor
    static func watch(
        session: DemoDeparture.Session, mode: DemoAutoRide, location: DemoAutoRideLocation? = nil,
        lookInterval: Duration? = AutoRideDemo.lookInterval,
        start: @escaping @MainActor (Ride) async -> Bool, rideRuns: @escaping @MainActor () -> Bool,
        isDeclined: @escaping @MainActor (TripKey) -> Bool = { _ in false }
    ) -> AutoRideWatch {
        let plan = plan(on: session.day)
        let positions: any TrainPositionProviding = mode == .noFeed
            ? NoTrainPositions()
            : DemoTrainPositions(plan: plan, clock: session.clock)
        return AutoRideWatch(
            ride: nil,
            location: location ?? DemoAutoRideLocation(session: session, mode: mode),
            departures: DemoAutoRideDepartures(session: session),
            positions: positions,
            clock: session.clock,
            store: AutoRideStore(defaults: nil),
            live: true,
            demo: true,
            lookInterval: lookInterval,
            startRide: start,
            isDeclined: isDeclined,
            rideRuns: rideRuns,
            reportsStationary: true
        )
    }

    /// The demo train, from its departure before it leaves: what the watch arms with.
    static func candidate(_ session: DemoDeparture.Session, at now: Date) -> AutoRideWatch.Candidate? {
        guard let departure = session.departure(at: now) else { return nil }
        return AutoRideWatch.Candidate(route: session.route, departure: departure)
    }
}

/// The demo train's live status: the demo departure's, on time and then 3 min late.
struct DemoAutoRideDepartures: AutoRideDepartureReading {
    let session: DemoDeparture.Session

    func departure(of trip: Trip, ride: Ride, at now: Date) async -> Departure? {
        session.departure(at: now)
    }
}

/// No train positions: the demo's No feed.
struct NoTrainPositions: TrainPositionProviding {
    func position(of trip: TripKey) async -> TrainPosition? { nil }
}

/// The demo phone (TT-242). Boards and No feed: no fix while the train stands under Union's shed (the first 300 m), then a
/// fix on the track where the train is by the demo's clock, as a phone on board would see it; Stays: a stationary fix at
/// Union's platform. Allowed with Precise Location from the start, so it never asks.
@MainActor
final class DemoAutoRideLocation: LocationProviding {
    private let plan: RidePlan
    private let clock: any AppClock
    private let mode: DemoAutoRide
    private let interval: Duration?
    private var updates: Task<Void, Never>?
    private var onFix: (@MainActor @Sendable (LocationFix) -> Void)?

    /// `interval` nil runs no timer: tests send each fix with `tick()`.
    init(session: DemoDeparture.Session, mode: DemoAutoRide, interval: Duration? = AutoRideDemo.fixInterval) {
        plan = AutoRideDemo.plan(on: session.day)
        clock = session.clock
        self.mode = mode
        self.interval = interval
    }

    var isAuthorized: Bool { true }
    var canAsk: Bool { false }
    var isPrecise: Bool { true }
    /// Its watch is listening (tests).
    var isUpdating: Bool { onFix != nil }

    func requestWhenInUse() async -> Bool { true }

    func startUpdates(_ onFix: @escaping @MainActor @Sendable (LocationFix) -> Void) {
        stopUpdates()
        self.onFix = onFix
        tick()
        guard let interval else { return }
        // Ends with its phone: a watch dropped without stopping it leaves no timer behind.
        updates = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    func stopUpdates() {
        updates?.cancel()
        updates = nil
        onFix = nil
    }

    /// Sends the fix at the demo clock's moment, if there is one.
    func tick() {
        if let fix = fix() { onFix?(fix) }
    }

    /// The fix at the demo clock's moment; nil while a phone on board is still under the shed.
    func fix() -> LocationFix? {
        guard let track = plan.track else { return nil }
        let origin = track.stopDistances[0]
        switch mode {
        case .stays:
            return LocationFix(coordinate: track.shape.point(at: origin), horizontalAccuracy: 8, isStationary: true)
        case .boards, .noFeed:
            let along = plan.scheduledAlong(at: clock.now)
            guard along - origin >= AutoRideRule.leaveAlong else { return nil }
            return LocationFix(coordinate: track.shape.point(at: along), horizontalAccuracy: 8)
        case .off:
            return nil
        }
    }
}
