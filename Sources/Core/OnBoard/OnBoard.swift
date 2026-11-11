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
    /// Demo trains › Departure (TT-177): the demo's before-departure window while it plays. It keeps playing under the
    /// demo ride its "I’m on board" starts, and shows again once that ride is ended.
    private(set) var departureDemo: DemoDeparture.Session?
    /// The demo ride was started by the demo departure's "I’m on board": End ride stops it.
    private var demoIsHandOff = false
    private let makeDeparture: @MainActor () -> DemoDeparture.Session
    private let makeHandOff: @MainActor (DemoDeparture.Session) -> (engine: RideEngine, ride: Ride)
    /// The app engine's arriving nudge (TT-173), which `AppDelegate` makes and follows from launch.
    private let nudge: ArrivalNudge?
    /// The demo ride's nudge, made each time a demo ride starts.
    @ObservationIgnored private var demoNudge: ArrivalNudge?
    private let makeDemoNudge: @MainActor () -> ArrivalNudge?
    /// The notification prompt through the alert rules (D41, D66), after a ride started.
    private let requestNotifications: @MainActor () async -> Void

    init(
        app: RideEngine?,
        detector: TrainDetector? = nil,
        makeDemo: @escaping @MainActor (Date?) -> (engine: RideEngine, ride: Ride) = { DemoRide.session(from: $0) },
        makeDemoDetector: (@MainActor () -> TrainDetector)? = { DemoRide.detector() },
        makeDeparture: @escaping @MainActor () -> DemoDeparture.Session = { DemoDeparture.session() },
        makeHandOff: @escaping @MainActor (DemoDeparture.Session) -> (engine: RideEngine, ride: Ride) = {
            DemoRide.session(continuing: $0)
        },
        nudge: ArrivalNudge? = nil,
        makeDemoNudge: @escaping @MainActor () -> ArrivalNudge? = { nil },
        requestNotifications: @escaping @MainActor () async -> Void = {}
    ) {
        self.app = app
        self.detector = detector
        self.makeDemo = makeDemo
        self.makeDemoDetector = makeDemoDetector
        self.makeDeparture = makeDeparture
        self.makeHandOff = makeHandOff
        self.nudge = nudge
        self.makeDemoNudge = makeDemoNudge
        self.requestNotifications = requestNotifications
    }

    /// The demo's engine while it plays, else the app's.
    var engine: RideEngine? { demo ?? app }

    /// "I'm on board" can start a ride: the app has the GO feed's trips (fixture runs have none) and no demo plays.
    var canStart: Bool { (demo == nil || handOffEnded) && !playsDemo && app?.canStart == true }

    /// The demo departure's ride ended on its own, 10 min after its last stop (TT-177): it no longer stands in for the
    /// app's engine, so a real ride (train detection's Yes, "I’m on board") can start.
    private var handOffEnded: Bool { demoIsHandOff && activeRide == nil }

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

    /// "I'm on board" (or the question's Yes): starts the ride on the app's engine, where location is asked, then asks for
    /// notifications if they were never asked, for the arriving notifications (TT-173). False when it did not start.
    @discardableResult
    func start(_ ride: Ride, on route: Route) async -> Bool {
        if handOffEnded {
            demo = nil
            demoIsHandOff = false
        }
        guard let app, demo == nil else { return false }
        let started = await app.start(ride)
        guard started else { return false }
        self.route = route
        await requestNotifications()
        nudge?.replan()
        return true
    }

    /// End ride, or Done at your stop. A demo ride the demo departure started stops with it, so the departure shows again.
    func end() {
        engine?.end()
        if demoIsHandOff {
            dropDemoNudge()
            demo = nil
            demoIsHandOff = false
        }
    }

    /// Demo trains › Ride turned on or off: the demo's question plays when Schedule shows (its ride starts on Yes), or
    /// with no question the ride starts from 5:32 PM; off, it stops and leaves the app's engine as it was.
    func setDemo(_ isOn: Bool) async {
        playsDemo = isOn
        if isOn {
            guard demo == nil, makeDemoDetector == nil else { return }
            let session = makeDemo(nil)
            demo = session.engine
            followDemo(session.engine)
            await session.engine.start(session.ride)
        } else {
            dropDemoNudge()
            demo?.end()
            demo = nil
            demoDetector = nil
            demoIsHandOff = false
        }
    }

    /// The demo ride's own nudge (TT-173), on its 6x clock, replacing an earlier demo ride's.
    private func followDemo(_ engine: RideEngine) {
        demoNudge?.stop()
        demoNudge = makeDemoNudge()
        demoNudge?.follow(engine)
    }

    /// The demo ride is dropped: its nudge stops and removes what it scheduled.
    private func dropDemoNudge() {
        demoNudge?.stop()
        demoNudge = nil
    }

    /// Demo trains › Departure turned on or off (TT-177): the demo window plays from 5:01 PM, or stops, with the demo ride
    /// its "I’m on board" started.
    func setDemoDeparture(_ isOn: Bool) {
        if isOn {
            if departureDemo == nil { departureDemo = makeDeparture() }
        } else {
            departureDemo = nil
            if demoIsHandOff {
                dropDemoNudge()
                demo?.end()
                demo = nil
                demoIsHandOff = false
            }
        }
    }

    /// "I’m on board" in the demo departure: the demo ride starts from the demo's time. It takes the sheet over only once
    /// it runs, in one update, so the departure card turns into the ride with nothing between them. False when no demo
    /// departure plays or the ride did not start.
    @discardableResult
    func handOffDemo() async -> Bool {
        guard let session = departureDemo else { return false }
        let handOff = makeHandOff(session)
        // Its own arriving nudge (TT-173), following before the ride starts so it sees the first update.
        let handOffNudge = makeDemoNudge()
        handOffNudge?.follow(handOff.engine)
        guard await handOff.engine.start(handOff.ride) else {
            handOffNudge?.stop()
            return false
        }
        demoNudge?.stop()
        demoNudge = handOffNudge
        demo?.end()
        demo = handOff.engine
        demoIsHandOff = true
        return true
    }

    // MARK: Train detection (TT-175)

    /// What the strip under the day strip shows instead of the ride: the matcher checking, or its question; nothing while
    /// a ride runs.
    var detection: TrainMatcher.State {
        guard activeRide == nil else { return .idle }
        return (demoDetector ?? detector)?.state ?? .idle
    }

    /// Runs train detection while Schedule is open, until the screen goes: the demo's question while Demo trains › Ride is
    /// on (once, until it is turned off and on), else the app's detector on `route`, paused while a ride runs.
    func detect(on route: Route, demo isDemo: Bool) async {
        if isDemo {
            guard activeRide == nil, demo == nil, let makeDemoDetector else { return }
            if let current = demoDetector {
                // A No keeps the demo quiet until it is turned off and on.
                guard current.silenced.isEmpty else { return }
                // A question not yet asked starts again from 5:18 PM, so the rider sees it from the start.
                if !current.isAsking { demoDetector = makeDemoDetector() }
            } else {
                demoDetector = makeDemoDetector()
            }
            await demoDetector?.run(on: DemoRide.route)
            return
        }
        guard let detector else { return }
        while !Task.isCancelled {
            if activeRide == nil {
                await detector.run(on: route) { [weak self] in self?.activeRide == nil }
            }
            // A ride runs, or location is not allowed yet: look again shortly, so detection resumes when the ride ends.
            try? await Task.sleep(for: Self.detectRetry)
        }
    }

    static let detectRetry: Duration = .seconds(5)

    /// Yes on the question: the ride on that train starts, the demo's on its own engine from where its clock is. The only
    /// way the matcher leads to a ride; false when it did not start.
    @discardableResult
    func accept(_ train: TrainCandidate) async -> Bool {
        // A second tap while the first starts the ride does nothing.
        guard !isAccepting else { return false }
        isAccepting = true
        defer { isAccepting = false }
        if let question = demoDetector {
            // The demo clock where the question was asked: it ran on while the question waited.
            var moment = question.now
            if case .asking(let asked) = question.state { moment = asked.askedAt }
            let session = makeDemo(moment)
            demo = session.engine
            followDemo(session.engine)
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
