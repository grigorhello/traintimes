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
    /// The demo ride's engine while Demo trains › Ride is on, from the question's Yes. The Live Activity follows whichever
    /// demo engine plays, however it was started or stopped (TT-174).
    private(set) var demo: RideEngine? {
        didSet { if demo !== oldValue { liveActivity?.follow(demo: demo) } }
    }
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
    /// The ride's Live Activity (TT-174), which follows the demo's engine while it plays; nil in previews and tests.
    private let liveActivity: (any RideActivityFollowing)?
    /// The app engine's arriving nudge (TT-173), which `AppDelegate` makes and follows from launch.
    private let nudge: ArrivalNudge?
    /// The demo ride's nudge, made each time a demo ride starts.
    @ObservationIgnored private var demoNudge: ArrivalNudge?
    private let makeDemoNudge: @MainActor () -> ArrivalNudge?
    /// The notification prompt through the alert rules (D41, D66), after a ride started.
    private let requestNotifications: @MainActor () async -> Void
    /// The arrival wish of the ride on screen and its analytics (TT-223, D103).
    let wishes: ArrivalWishes
    /// The ride screen's Tick and Tap and its watch time (TT-224, D106).
    let screen: RideScreen

    /// The detection question's feels (TT-215, D100): Rail joint on Yes at the tap, Tap on No.
    private let haptics: any HapticPlaying
    /// Where a No on the departure question is kept for the day (TT-231): `.standard` in the app, nil in tests.
    private let declines: UserDefaults?
    /// Schedule's question when the alerted train has left (TT-231, D110), set by `RootView` while Schedule shows.
    private(set) var departureAsk: DepartureAsk?
    /// Demo departures declined while the app runs: the demo is not kept on device.
    @ObservationIgnored private var declinedDemo: Set<Ride> = []
    /// The app's automatic ride watch (TT-242, D120, `AppDelegate.autoRide`); nil in fixture runs, previews and tests.
    let autoRide: AutoRideWatch?
    /// Settings › Testing › Demo trains › Depart › Automatic ride: the demo watch while the demo departure plays.
    private(set) var autoRideDemo: AutoRideWatch?
    private var demoAutoRideMode: DemoAutoRide = .off
    private let makeAutoRideDemo: @MainActor (DemoDeparture.Session, DemoAutoRide, OnBoard) -> AutoRideWatch
    /// Arms the demo watch on each play of the demo before its train leaves.
    @ObservationIgnored private var autoRideDemoLoop: Task<Void, Never>?

    init(
        app: RideEngine?,
        detector: TrainDetector? = nil,
        liveActivity: (any RideActivityFollowing)? = nil,
        makeDemo: @escaping @MainActor (Date?) -> (engine: RideEngine, ride: Ride) = { DemoRide.session(from: $0) },
        makeDemoDetector: (@MainActor () -> TrainDetector)? = { DemoRide.detector() },
        makeDeparture: @escaping @MainActor () -> DemoDeparture.Session = { DemoDeparture.session() },
        makeHandOff: @escaping @MainActor (DemoDeparture.Session) -> (engine: RideEngine, ride: Ride) = {
            DemoRide.session(continuing: $0)
        },
        nudge: ArrivalNudge? = nil,
        makeDemoNudge: @escaping @MainActor () -> ArrivalNudge? = { nil },
        requestNotifications: @escaping @MainActor () async -> Void = {},
        wishes: ArrivalWishes? = nil,
        haptics: any HapticPlaying = TTHaptics.shared,
        screen: RideScreen? = nil,
        declines: UserDefaults? = nil,
        autoRide: AutoRideWatch? = nil,
        makeAutoRideDemo: @escaping @MainActor (DemoDeparture.Session, DemoAutoRide, OnBoard) -> AutoRideWatch = {
            OnBoard.demoWatch(session: $0, mode: $1, onBoard: $2)
        }
    ) {
        self.autoRide = autoRide
        self.makeAutoRideDemo = makeAutoRideDemo
        self.haptics = haptics
        self.declines = declines
        self.app = app
        self.detector = detector
        self.liveActivity = liveActivity
        self.makeDemo = makeDemo
        self.makeDemoDetector = makeDemoDetector
        self.makeDeparture = makeDeparture
        self.makeHandOff = makeHandOff
        self.nudge = nudge
        self.makeDemoNudge = makeDemoNudge
        self.requestNotifications = requestNotifications
        self.wishes = wishes ?? ArrivalWishes(defaults: nil, haptics: haptics)
        self.screen = screen ?? RideScreen(haptics: haptics)
    }

    /// The demo's engine while it plays, else the app's.
    var engine: RideEngine? { demo ?? app }

    /// "I'm on board" can start a ride: the app has the GO feed's trips (fixture runs have none) and no demo plays.
    var canStart: Bool { (demo == nil || handOffEnded) && !playsDemo && app?.canStart == true }

    /// The demo departure's ride ended on its own, 2 min after its last stop (TT-177, D103): it no longer stands in for the
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

    /// This trip's ride ended at your stop, 2 min after the train got there (D103).
    func endedAtYourStop(_ key: TripKey) -> Bool {
        guard let engine, engine.ride?.tripKey == key, let state = engine.state else { return false }
        return state.phase == .ended && state.endReason == .arrived
    }

    /// The arrival wish (TT-223, D103) in "Now"'s place: 5 s after the train reached your stop (5 s on the real clock, so
    /// 30 s on the demo ride's 6x one), while the ride is at your stop or ended there. One wish per ride.
    var arrivalWish: ArrivalWish? {
        guard let engine, let ride = engine.ride, let state = engine.state, let arrivedAt = engine.arrivedAt,
              let startedAt = engine.startedAt,
              state.phase == .atYourStop || (state.phase == .ended && state.endReason == .arrived) else { return nil }
        let isDemo = demo != nil
        guard engine.now.timeIntervalSince(arrivedAt) >= ArrivalWishes.delay * (isDemo ? DemoRide.speed : 1) else { return nil }
        // Demo rides all start at 5:32 PM on the same trip: the engine, new for each, tells them apart.
        let engineID = isDemo ? "|\(ObjectIdentifier(engine).hashValue)" : ""
        let id = "\(ride.tripId)|\(ride.serviceDate)|\(startedAt.timeIntervalSince1970)\(engineID)"
        return wishes.wish(for: id, arrivedAt: arrivedAt, demo: isDemo)
    }

    /// "I'm on board" (or the question's Yes): starts the ride on the app's engine, where location is asked, then asks for
    /// notifications if they were never asked, for the arriving notifications (TT-173). False when it did not start.
    @discardableResult
    func start(_ ride: Ride, on route: Route, source: RideStartSource = .onBoard) async -> Bool {
        if handOffEnded {
            demo = nil
            demoIsHandOff = false
        }
        guard let app, demo == nil else { return false }
        let started = await app.start(ride, source: source)
        guard started else { return false }
        Analytics.track(.rideStarted(source: source, demo: false, plan: app.plan))
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
            if departureDemo == nil {
                departureDemo = makeDeparture()
                startAutoRideDemo()
            }
        } else {
            departureDemo = nil
            startAutoRideDemo()
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
    /// departure plays or the ride did not start. `source`: how it started, `auto` for the demo watch (TT-242).
    @discardableResult
    func handOffDemo(source: RideStartSource = .onBoard) async -> Bool {
        guard let session = departureDemo else { return false }
        let handOff = makeHandOff(session)
        // Its own arriving nudge (TT-173), following before the ride starts so it sees the first update.
        let handOffNudge = makeDemoNudge()
        handOffNudge?.follow(handOff.engine)
        guard await handOff.engine.start(handOff.ride, source: source) else {
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

    /// Start On board on the demo's background question (TT-176; Debug and TestFlight builds, as a test push sends it): the
    /// demo ride from 5:32 PM on its own engine, which End ride stops, as the demo departure's ride (TT-177). False when a
    /// ride already runs.
    @discardableResult
    func startDemoRide() async -> Bool {
        guard activeRide == nil else { return false }
        let session = makeDemo(nil)
        // Its own arriving nudge (TT-173), as the demo departure's ride.
        let rideNudge = makeDemoNudge()
        rideNudge?.follow(session.engine)
        guard await session.engine.start(session.ride) else {
            rideNudge?.stop()
            return false
        }
        demoNudge?.stop()
        demoNudge = rideNudge
        demo?.end()
        demo = session.engine
        demoIsHandOff = true
        return true
    }

    // MARK: Automatic ride (TT-242, D120)

    /// The ride that started by itself, the demo's or the app's, and when: ride mode opens once for it (`RootView`).
    var autoRideStarted: AutoRideWatch.Started? {
        autoRideDemo?.started ?? autoRide?.started
    }

    /// Settings › Testing › Last check: the demo watch's while it plays, else the app's.
    var autoRideCheck: AutoRideCheck? {
        autoRideDemo?.lastCheck ?? autoRide?.lastCheck
    }

    /// Settings › Testing › Demo trains › Depart › Automatic ride changed (TT-242): the demo watch starts again with it.
    func setDemoAutoRide(_ mode: DemoAutoRide) {
        guard mode != demoAutoRideMode else { return }
        demoAutoRideMode = mode
        startAutoRideDemo()
    }

    /// The demo watch for the chosen mode while the demo departure plays, armed on each play before its train leaves and
    /// while no ride runs; none otherwise.
    private func startAutoRideDemo() {
        autoRideDemoLoop?.cancel()
        autoRideDemoLoop = nil
        autoRideDemo?.stop()
        autoRideDemo = nil
        guard demoAutoRideMode != .off, let session = departureDemo else { return }
        let watch = makeAutoRideDemo(session, demoAutoRideMode, self)
        autoRideDemo = watch
        armAutoRideDemo()
        autoRideDemoLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.armAutoRideDemo()
            }
        }
    }

    /// Arms the demo watch when it watches nothing, no ride runs, the demo's train was not declined and has not left yet. A watch the demo's
    /// clock went back on (its next play from 5:01 PM) ends as its question would have.
    func armAutoRideDemo() {
        guard let watch = autoRideDemo, let session = departureDemo else { return }
        let now = session.now
        if let watched = watch.watched, now < max(watched.armedAt, watched.lastLook ?? watched.armedAt) {
            watch.questionEnded()
        }
        guard watch.watched == nil, activeRide == nil else { return }
        // A demo train declined this run is never watched again: it would end as answered at once, every second.
        guard !declinedDemo.contains(where: { $0.tripKey == session.key }) else { return }
        guard let candidate = AutoRideDemo.candidate(session, at: now), now < candidate.departure else { return }
        watch.watchDemo(candidate, plan: AutoRideDemo.plan(on: session.day))
    }

    /// The demo watch as Settings › Testing plays it: its start is the demo departure's hand-off.
    static func demoWatch(session: DemoDeparture.Session, mode: DemoAutoRide, onBoard: OnBoard) -> AutoRideWatch {
        AutoRideDemo.watch(
            session: session, mode: mode,
            start: { [weak onBoard] _ in await onBoard?.handOffDemo(source: .auto) ?? false },
            rideRuns: { [weak onBoard] in onBoard?.activeRide != nil },
            isDeclined: { [weak onBoard] key in onBoard?.declinedDemo.contains { $0.tripKey == key } ?? false }
        )
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
        haptics.play(.onBoard)
        isAccepting = true
        defer { isAccepting = false }
        if let question = demoDetector {
            // The demo clock where the question was asked: it ran on while the question waited.
            var moment = question.now
            if case .asking(let asked) = question.state { moment = asked.askedAt }
            let session = makeDemo(moment)
            demo = session.engine
            followDemo(session.engine)
            let started = await session.engine.start(session.ride, source: .detection)
            Analytics.track(.detectionAnswered(yes: true))
            if started { Analytics.track(.rideStarted(source: .detection, demo: true, plan: session.engine.plan)) }
            // The question stays until the ride shows, so the strip goes straight from one to the other.
            demoDetector = nil
            return started
        }
        Analytics.track(.detectionAnswered(yes: true))
        guard let detector, await start(train.ride, on: train.route, source: .detection) else { return false }
        detector.accepted()
        return true
    }

    /// No on the question: its trains are not asked about again today.
    func decline() {
        haptics.play(.undo)
        Analytics.track(.detectionAnswered(yes: false))
        (demoDetector ?? detector)?.decline()
    }

    // MARK: The departure question (TT-231)

    /// The Live Activity's train at its clock (`DepartureActivitySource`): Schedule asks about it once it has left, while no
    /// ride runs and it was not declined today; nil clears the question (Schedule went, the window ended).
    func updateDepartureAsk(_ live: LiveDeparture?, route: Route?, isDemo: Bool) {
        var ask: DepartureAsk?
        if let live, let route {
            let candidate = DepartureAsk(live: live, route: route, isDemo: isDemo)
            if DepartureQuestion.asks(live, isRiding: activeRide != nil, isDeclined: isDeclined(candidate)) { ask = candidate }
        }
        if ask != departureAsk { departureAsk = ask }
    }

    /// No train detection question shows: detection's own question wins the strip.
    var asksDeparture: Bool {
        guard departureAsk != nil, activeRide == nil else { return false }
        if case .asking = detection { return false }
        return true
    }

    /// The train was declined today: on the card, the notification or Schedule's strip, or on detection's question.
    func isDeclined(_ ask: DepartureAsk) -> Bool {
        ask.isDemo ? declinedDemo.contains(ask.ride) : DepartureQuestion.isDeclined(ask.ride.tripKey, in: declines)
    }

    /// Yes on Schedule's strip: Rail joint at the tap, and the ride starts (the demo's hands over into the demo ride).
    @discardableResult
    func acceptDeparture() async -> Bool {
        guard let ask = departureAsk, !isAccepting else { return false }
        haptics.play(.onBoard)
        isAccepting = true
        defer { isAccepting = false }
        Analytics.track(.departureQuestionAnswered(yes: true, surface: .schedule))
        let started: Bool
        if ask.isDemo {
            started = await handOffDemo(source: .departure)
            if started { Analytics.track(.rideStarted(source: .departure, demo: true)) }
        } else {
            started = await start(ask.ride, on: ask.route, source: .departure)
        }
        if started { departureAsk = nil }
        return started
    }

    /// No on Schedule's strip: nothing asks about that train again today, and its card leaves the Lock Screen.
    func declineDeparture() {
        guard let ask = departureAsk else { return }
        haptics.play(.undo)
        if ask.isDemo {
            declinedDemo.insert(ask.ride)
            Analytics.track(.departureQuestionAnswered(yes: false, surface: .schedule))
        } else {
            DepartureQuestion.decline(ask.ride.tripKey, in: declines, surface: .schedule)
        }
        liveActivity?.declineDeparture(ask.ride)
        departureAsk = nil
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

/// The ride's Live Activity on the Lock Screen and in the Dynamic Island (TT-174, `RideLiveActivity`): it follows the app's
/// engine, and the demo's while Demo trains › Ride plays.
@MainActor
protocol RideActivityFollowing: AnyObject {
    func follow(demo engine: RideEngine?)
    /// No on the departure question in the app (TT-231): that train's card leaves the Lock Screen, and the alert server
    /// sends nothing more for it.
    func declineDeparture(_ ride: Ride)
}

extension RideActivityFollowing {
    func declineDeparture(_ ride: Ride) {}
}
