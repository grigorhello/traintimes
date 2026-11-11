import Foundation
import Observation

/// On board as the screens see it (TT-172): the app's ride engine, or the demo ride's while Settings › Testing › Demo
/// trains › Ride is on. One per app, made in `RootView` and shared by Trip details (the button and ride mode) and
/// Schedule (the ride strip, and train detection's strip and question, TT-175).
@Observable @MainActor
final class OnBoard {
    /// The app's engine (`AppDelegate.ride`); nil in previews and in tests that need no ride.
    private let app: RideEngine?
    /// The app's train detector (TT-175); nil in fixture runs, previews and most tests.
    private let detector: TrainDetector?
    /// The demo ride's engine while Demo trains › Ride is on, from the question's Yes.
    private(set) var demo: RideEngine?
    /// The demo question's detector, until its Yes (TT-175).
    private(set) var demoDetector: TrainDetector?
    /// Demo trains › Ride is on.
    private(set) var playsDemo = false
    /// The route the ride was started on, for the sheet's header when the strip opens it.
    private(set) var route: Route?
    /// The demo ride, from the moment on its clock where the question's Yes left it (nil: from 5:32 PM).
    private let makeDemo: @MainActor (Date?) -> (engine: RideEngine, ride: Ride)
    /// The demo question; nil starts the demo ride at once (ride tests).
    private let makeDemoDetector: (@MainActor () -> TrainDetector)?
    @ObservationIgnored private var isAccepting = false

    init(
        app: RideEngine?,
        detector: TrainDetector? = nil,
        makeDemo: @escaping @MainActor (Date?) -> (engine: RideEngine, ride: Ride) = { DemoRide.session(from: $0) },
        makeDemoDetector: (@MainActor () -> TrainDetector)? = { DemoRide.detector() }
    ) {
        self.app = app
        self.detector = detector
        self.makeDemo = makeDemo
        self.makeDemoDetector = makeDemoDetector
    }

    /// The demo's engine while it plays, else the app's.
    var engine: RideEngine? { demo ?? app }

    /// "I'm on board" can start a ride: the app has the GO feed's trips (fixture runs have none) and no demo plays.
    var canStart: Bool { demo == nil && !playsDemo && app?.canStart == true }

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

    /// End ride, or Done at your stop.
    func end() {
        engine?.end()
    }

    /// Demo trains › Ride turned on or off: the demo's question plays when Schedule shows (its ride starts on Yes), or
    /// with no question the ride starts from 5:32 PM; off, it stops and leaves the app's engine as it was.
    func setDemo(_ isOn: Bool) async {
        playsDemo = isOn
        if isOn {
            guard demo == nil, makeDemoDetector == nil else { return }
            let session = makeDemo(nil)
            demo = session.engine
            await session.engine.start(session.ride)
        } else {
            demo?.end()
            demo = nil
            demoDetector = nil
        }
    }

    // MARK: Train detection (TT-175)

    /// What the strip under the day strip shows instead of the ride: the matcher checking, or its question; nothing while
    /// a ride runs.
    var detection: TrainMatcher.State {
        guard activeRide == nil else { return .idle }
        return (demoDetector ?? detector)?.state ?? .idle
    }

    /// Runs train detection while Schedule is open, until the screen goes or a ride starts: the demo's question while Demo
    /// trains › Ride is on (once, until it is turned off and on), else the app's detector on `route`.
    func detect(on route: Route, demo isDemo: Bool) async {
        guard activeRide == nil else { return }
        if isDemo {
            guard demo == nil, let makeDemoDetector else { return }
            // A question not yet asked starts again from 5:18 PM, so the rider sees it from the start.
            if demoDetector?.isAsking != true { demoDetector = makeDemoDetector() }
            await demoDetector?.run(on: DemoRide.route)
        } else {
            await detector?.run(on: route) { [weak self] in self?.activeRide == nil }
        }
    }

    /// Yes on the question: the ride on that train starts, the demo's on its own engine from where its clock is. The only
    /// way the matcher leads to a ride; false when it did not start.
    @discardableResult
    func accept(_ train: TrainCandidate) async -> Bool {
        // A second tap while the first starts the ride does nothing.
        guard !isAccepting else { return false }
        isAccepting = true
        defer { isAccepting = false }
        if let question = demoDetector {
            let session = makeDemo(question.now)
            demo = session.engine
            let started = await session.engine.start(session.ride)
            // The question stays until the ride shows, so the strip goes straight from one to the other.
            demoDetector = nil
            return started
        }
        guard let detector, await start(train.ride, on: train.route) else { return false }
        detector.accepted()
        return true
    }

    /// No on the question: its trains are not asked about again today.
    func decline() {
        (demoDetector ?? detector)?.decline()
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
