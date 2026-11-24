import Foundation
import Observation

/// On board as the screens see it (TT-172): the app's ride engine, or the demo ride's while Settings › Testing › Demo
/// trains › Ride is on. One per app, made in `RootView` and shared by Trip details (the button and ride mode) and
/// Schedule (the ride strip and the departure question, TT-231).
@Observable @MainActor
final class OnBoard {
    /// The app's engine (`AppDelegate.ride`); nil in previews and in tests that need no ride.
    private let app: RideEngine?
    /// The demo ride's engine while Demo trains › Ride is on, or the demo departure's hand-off. The Live Activity follows
    /// whichever demo engine plays, however it was started or stopped (TT-174).
    private(set) var demo: RideEngine? {
        didSet { if demo !== oldValue { liveActivity?.follow(demo: demo) } }
    }
    /// Demo trains › Ride is on.
    private(set) var playsDemo = false
    /// The route the ride was started on, for the sheet's header when the strip opens it.
    private(set) var route: Route?
    /// The demo ride, from a moment on its clock (nil: from 5:32 PM).
    private let makeDemo: @MainActor (Date?) -> (engine: RideEngine, ride: Ride)
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

    /// The departure question's feels (TT-215, D100): Rail joint on Yes at the tap, Tap on No.
    private let haptics: any HapticPlaying
    /// Where a No on the departure question is kept for the day (TT-231): `.standard` in the app, nil in tests.
    private let declines: UserDefaults?
    /// Schedule's question when the alerted train has left (TT-231, D110), set by `RootView` while Schedule shows.
    private(set) var departureAsk: DepartureAsk?
    /// Demo departures declined while the app runs: the demo is not kept on device.
    @ObservationIgnored private var declinedDemo: Set<Ride> = []
    /// The app's automatic ride watch (TT-242, D120, `AppDelegate.autoRide`); nil in fixture runs, previews and tests.
    let autoRide: AutoRideWatch?
    /// What the automatic ride keeps on device (TT-243): Not on it's count and the one-time strip; nil keeps nothing.
    private let autoRideStore: AutoRideStore?
    /// Settings › Testing › Demo trains › Depart › Automatic ride: the demo watch while the demo departure plays.
    private(set) var autoRideDemo: AutoRideWatch?
    private var demoAutoRideMode: DemoAutoRide = .off
    private let makeAutoRideDemo: @MainActor (DemoDeparture.Session, DemoAutoRide, OnBoard) -> AutoRideWatch
    /// Arms the demo watch on each play of the demo before its train leaves.
    @ObservationIgnored private var autoRideDemoLoop: Task<Void, Never>?

    init(
        app: RideEngine?,
        liveActivity: (any RideActivityFollowing)? = nil,
        makeDemo: @escaping @MainActor (Date?) -> (engine: RideEngine, ride: Ride) = { DemoRide.session(from: $0) },
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
        autoRideStore: AutoRideStore? = nil,
        makeAutoRideDemo: @escaping @MainActor (DemoDeparture.Session, DemoAutoRide, OnBoard) -> AutoRideWatch = {
            OnBoard.demoWatch(session: $0, mode: $1, onBoard: $2)
        }
    ) {
        self.autoRide = autoRide
        self.autoRideStore = autoRideStore
        self.makeAutoRideDemo = makeAutoRideDemo
        self.haptics = haptics
        self.declines = declines
        self.app = app
        self.liveActivity = liveActivity
        self.makeDemo = makeDemo
        self.makeDeparture = makeDeparture
        self.makeHandOff = makeHandOff
        self.nudge = nudge
        self.makeDemoNudge = makeDemoNudge
        self.requestNotifications = requestNotifications
        self.wishes = wishes ?? ArrivalWishes(defaults: nil, haptics: haptics)
        self.screen = screen ?? RideScreen(haptics: haptics)
        liveActivity?.demoNotOnIt = { [weak self] ride in self?.demoCardNotOnIt(ride) }
    }

    /// The demo's engine while it plays, else the app's.
    var engine: RideEngine? { demo ?? app }

    /// "I'm on board" can start a ride: the app has the GO feed's trips (fixture runs have none) and no demo plays.
    var canStart: Bool { (demo == nil || handOffEnded) && !playsDemo && app?.canStart == true }

    /// The demo departure's ride ended on its own, 2 min after its last stop (TT-177, D103): it no longer stands in for the
    /// app's engine, so a real ride ("I’m on board", the departure question's Yes) can start.
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

    /// This trip's ride ended by Not on it or by itself, in its first 10 min after it started by itself (TT-243, D120).
    func endedUndone(_ key: TripKey) -> Bool {
        guard let engine, engine.ride?.tripKey == key, let state = engine.state, state.phase == .ended else { return false }
        return state.endReason == .notOnIt || state.endReason == .autoUndone
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

    /// "I'm on board" (or the departure question's Yes): starts the ride on the app's engine, where location is asked, then asks for
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

    /// Demo trains › Ride turned on or off: the demo ride starts at once from 5:32 PM (TT-243: the question before it went
    /// with train detection); off, it stops and leaves the app's engine as it was.
    func setDemo(_ isOn: Bool) async {
        playsDemo = isOn
        if isOn {
            guard demo == nil else { return }
            let session = makeDemo(nil)
            demo = session.engine
            followDemo(session.engine)
            await session.engine.start(session.ride)
        } else {
            dropDemoNudge()
            demo?.end()
            demo = nil
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

    /// The demo watch as Settings › Testing plays it: its start is the demo departure's hand-off, which makes the one-time
    /// strip due as a real start does (TT-243), so it can be checked at a desk.
    static func demoWatch(session: DemoDeparture.Session, mode: DemoAutoRide, onBoard: OnBoard) -> AutoRideWatch {
        AutoRideDemo.watch(
            session: session, mode: mode,
            start: { [weak onBoard] _ in
                guard let onBoard, await onBoard.handOffDemo(source: .auto) else { return false }
                onBoard.autoRideStore?.stripDue = true
                return true
            },
            rideRuns: { [weak onBoard] in onBoard?.activeRide != nil },
            isDeclined: { [weak onBoard] key in onBoard?.declinedDemo.contains { $0.tripKey == key } ?? false }
        )
    }

    // MARK: Not on it (TT-243, D120)

    /// When "Not on it" stops showing for the ride on screen: 10 min after it started by itself (the demo watch's too);
    /// nil for any other ride.
    var autoUndoUntil: Date? {
        guard activeRide != nil else { return nil }
        return engine?.autoUndoUntil
    }

    /// Not on it on the ride screen, in its first 10 min after it started by itself: the ride ends (its card, "Your stop is
    /// next" and the sheet with it), and nothing asks about that train again today. A real ride's train is declined in the
    /// store and the tap counts toward two in 14 days, which turn Automatic ride off; the demo's is declined for the run
    /// only and does not count. The haptic is the caller's. Nothing is reported to the server: the card was handed off.
    func notOnIt(surface: RideEndSurface = .ride) {
        guard let engine, autoUndoUntil != nil else { return }
        if engine === demo {
            // The ended demo stays the engine, so an open sheet sees its ride end (`endedUndone`); a real ride can start
            // after the demo departure's hand-off all the same (`handOffEnded`).
            if let ride = engine.end(.notOnIt, surface: surface) { declinedDemo.insert(ride) }
            return
        }
        guard engine.end(.notOnIt, surface: surface) != nil else { return }
        autoRideStore?.recordNotOnIt(at: engine.now)
    }

    /// Not on it on the demo ride's card (`NotOnTrainIntent`, which ended the card): as on the ride screen. The app's own
    /// ride is `AppDelegate`'s, which works before this exists.
    func demoCardNotOnIt(_ ride: Ride) {
        guard let demo, demo === engine, demo.ride == ride else { return }
        notOnIt(surface: .card)
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

    /// Schedule's strip asks the departure question: no ride runs.
    var asksDeparture: Bool {
        departureAsk != nil && activeRide == nil
    }

    /// The train was declined today: on the card, the notification or Schedule's strip, by Not on it or the undo by itself.
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
    /// Not on it on the demo ride's card (TT-243): `OnBoard` sets it, `AppDelegate` calls it for the demo's train.
    var demoNotOnIt: (@MainActor (Ride) -> Void)? { get set }
    /// No on the departure question in the app (TT-231): that train's card leaves the Lock Screen, and the alert server
    /// sends nothing more for it.
    func declineDeparture(_ ride: Ride)
}

extension RideActivityFollowing {
    func declineDeparture(_ ride: Ride) {}
}
