import Foundation
import Observation

/// On board as the screens see it (TT-172): the app's ride engine, or the demo ride's while Settings › Testing › Demo
/// trains › Ride is on. One per app, made in `RootView` and shared by Trip details (the button and ride mode) and
/// Schedule (the ride strip).
@Observable @MainActor
final class OnBoard {
    /// The app's engine (`AppDelegate.ride`); nil in previews and in tests that need no ride.
    private let app: RideEngine?
    /// The demo ride's engine while Demo trains › Ride is on.
    private(set) var demo: RideEngine?
    /// The route the ride was started on, for the sheet's header when the strip opens it.
    private(set) var route: Route?
    /// Demo trains › Departure (TT-177): the demo's before-departure window while it plays. It keeps playing under the
    /// demo ride its "I’m on board" starts, and shows again once that ride is ended.
    private(set) var departureDemo: DemoDeparture.Session?
    /// The demo ride was started by the demo departure's "I’m on board": End ride stops it.
    private var demoIsHandOff = false
    private let makeDemo: @MainActor () -> (engine: RideEngine, ride: Ride)
    private let makeDeparture: @MainActor () -> DemoDeparture.Session
    private let makeHandOff: @MainActor (DemoDeparture.Session) -> (engine: RideEngine, ride: Ride)

    init(
        app: RideEngine?,
        makeDemo: @escaping @MainActor () -> (engine: RideEngine, ride: Ride) = { DemoRide.session() },
        makeDeparture: @escaping @MainActor () -> DemoDeparture.Session = { DemoDeparture.session() },
        makeHandOff: @escaping @MainActor (DemoDeparture.Session) -> (engine: RideEngine, ride: Ride) = {
            DemoRide.session(continuing: $0)
        }
    ) {
        self.app = app
        self.makeDemo = makeDemo
        self.makeDeparture = makeDeparture
        self.makeHandOff = makeHandOff
    }

    /// The demo's engine while it plays, else the app's.
    var engine: RideEngine? { demo ?? app }

    /// "I'm on board" can start a ride: the app has the GO feed's trips (fixture runs have none) and no demo plays.
    var canStart: Bool { demo == nil && app?.canStart == true }

    /// The first "I'm on board" shows the app's sheet before the iOS prompt.
    var asksForLocation: Bool { app?.asksForLocation ?? false }

    /// The ride the strip shows: started and not ended.
    var activeRide: Ride? {
        guard let engine, let ride = engine.ride, let state = engine.state, state.phase != .ended else { return nil }
        return ride
    }

    /// This trip's ride runs: started and not ended.
    func isRunning(_ key: TripKey) -> Bool {
        activeRide?.tripKey == key
    }

    /// This trip's ride ended at your stop, 10 min after the train got there.
    func endedAtYourStop(_ key: TripKey) -> Bool {
        guard let engine, engine.ride?.tripKey == key, let state = engine.state else { return false }
        return state.phase == .ended && state.endReason == .arrived
    }

    /// "I'm on board": starts the ride on the app's engine, where location is asked. False when it did not start.
    @discardableResult
    func start(_ ride: Ride, on route: Route) async -> Bool {
        guard let app, demo == nil else { return false }
        let started = await app.start(ride)
        if started { self.route = route }
        return started
    }

    /// End ride, or Done at your stop. A demo ride the demo departure started stops with it, so the departure shows again.
    func end() {
        engine?.end()
        if demoIsHandOff {
            demo = nil
            demoIsHandOff = false
        }
    }

    /// Demo trains › Ride turned on or off: the demo starts from 5:32 PM, or stops and leaves the app's engine as it was.
    func setDemo(_ isOn: Bool) async {
        if isOn {
            guard demo == nil else { return }
            let session = makeDemo()
            demo = session.engine
            await session.engine.start(session.ride)
        } else {
            demo?.end()
            demo = nil
            demoIsHandOff = false
        }
    }

    /// Demo trains › Departure turned on or off (TT-177): the demo window plays from 5:01 PM, or stops.
    func setDemoDeparture(_ isOn: Bool) {
        if isOn {
            if departureDemo == nil { departureDemo = makeDeparture() }
        } else {
            departureDemo = nil
        }
    }

    /// "I’m on board" in the demo departure: the demo ride starts from the demo's time. It takes the sheet over only once
    /// it runs, in one update, so the departure card turns into the ride with nothing between them. False when no demo
    /// departure plays or the ride did not start.
    @discardableResult
    func handOffDemo() async -> Bool {
        guard let session = departureDemo else { return false }
        let handOff = makeHandOff(session)
        guard await handOff.engine.start(handOff.ride) else { return false }
        demo?.end()
        demo = handOff.engine
        demoIsHandOff = true
        return true
    }

    /// The route to open the ride's Trip details on: the demo's, the one it was started on, else its two stations' (a ride
    /// restored at launch); nil when a station is no longer in the schedule.
    func rideRoute(stations: any StationRepository) async -> Route? {
        if demo != nil { return DemoRide.route }
        guard let ride = activeRide else { return nil }
        if let route, route.from.id == ride.originId, route.to.id == ride.destinationId { return route }
        guard let all = try? await stations.stations(),
              let from = all.first(where: { $0.id == ride.originId }),
              let to = all.first(where: { $0.id == ride.destinationId }),
              let resolved = try? await stations.route(from: from, to: to) else { return nil }
        route = resolved
        return resolved
    }
}
