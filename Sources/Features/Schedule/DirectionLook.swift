import Observation
import SwiftUI

/// Who chose a route that Schedule shows (TT-234, D116).
enum RouteChoice: Sendable {
    /// The rider, by hand: the station picker, a Recent row, the welcome's route, the swap button. Kept until the app has
    /// been out of view for more than 10 min, and it sets the widgets' morning way.
    case byHand
    /// One train's link: a notification, the Live Activity, a widget's train row, Alerts' "Pick a new train". Kept as a
    /// choice by hand is and it ends this visit's look, but it leaves the morning way.
    case trainLink
    /// A widget's route link: neither. The look may still turn it.
    case widgetRoute
}

/// Told each time the rider's choice puts a route on Schedule (`ScheduleViewModel.choices`): Automatic direction's look.
@MainActor
protocol RouteChoiceFollowing: AnyObject {
    /// `route` shows on Schedule now, chosen by `choice`.
    func chose(_ route: Route, by choice: RouteChoice)
}

/// What the look needs from Schedule: its route, whether Today shows, and the silent turn.
@MainActor
protocol RouteTurning: AnyObject {
    var route: Route? { get }
    var isToday: Bool { get }
    /// Turns the route round with no haptic and no event (`ScheduleViewModel.turn()`).
    func turn() async
}

/// Automatic direction's capsule on Schedule (TT-234, D116), in the bell capsule's place when no bell capsule is up.
struct DirectionCapsule: Equatable, Identifiable {
    enum Kind: Equatable {
        /// "Now from Union" with Undo, 5 s.
        case turned(station: String)
        /// "Trains from Union?" with Switch, 5 s.
        case asks(station: String)
        /// "Won’t switch by itself for an hour", 2.5 s, no action.
        case kept
    }

    let id: Int
    let kind: Kind

    var hasAction: Bool { kind != .kept }

    /// The capsule's line in three parts: the words before the station's short name, the name, which alone may be cut
    /// short, and what follows it.
    var line: (before: String, name: String, after: String) {
        switch kind {
        case .turned(let station): Self.split(String(localized: "direction.capsule.turned"), around: station)
        case .asks(let station): Self.split(String(localized: "direction.capsule.ask"), around: station)
        case .kept: (before: String(localized: "direction.capsule.kept"), name: "", after: "")
        }
    }

    /// The whole line, as VoiceOver reads it.
    var words: String {
        let line = line
        return line.before + line.name + line.after
    }

    /// Undo on a turn, Switch on the question, none on the line after Undo.
    var actionKey: String? {
        switch kind {
        case .turned: "button.undo"
        case .asks: "direction.capsule.switch"
        case .kept: nil
        }
    }

    private static func split(_ format: String, around name: String) -> (before: String, name: String, after: String) {
        guard let range = format.range(of: "%@") else { return (format, "", "") }
        return (String(format[..<range.lowerBound]), name, String(format[range.upperBound...]))
    }
}

/// The direction capsule's own small model: what shows, its timer and the finger's hold. The durations are the bell
/// capsule's (`AlertDependencies.capsuleActionDuration`, `capsulePlainDuration`, which `TT_TOAST_SECONDS` sets).
@Observable
@MainActor
final class DirectionCapsuleModel {
    private(set) var shown: DirectionCapsule?

    private let actionDuration: Duration
    private let plainDuration: Duration
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var nextID = 0

    init(actionDuration: Duration = .seconds(5), plainDuration: Duration = .milliseconds(2500)) {
        self.actionDuration = actionDuration
        self.plainDuration = plainDuration
    }

    func show(_ kind: DirectionCapsule.Kind) {
        nextID += 1
        let capsule = DirectionCapsule(id: nextID, kind: kind)
        shown = capsule
        scheduleHide(capsule)
    }

    /// A finger on the capsule keeps it up; lifting it starts the time again.
    func hold(_ holding: Bool) {
        hideTask?.cancel()
        if !holding, let shown { scheduleHide(shown) }
    }

    func dismiss() {
        hideTask?.cancel()
        if shown != nil { shown = nil }
    }

    private func scheduleHide(_ capsule: DirectionCapsule) {
        hideTask?.cancel()
        let duration = capsule.hasAction ? actionDuration : plainDuration
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let self, self.shown?.id == capsule.id else { return }
            self.shown = nil
        }
    }
}

/// Automatic direction's look (TT-234, D116): once per visit, when Schedule is in front on Today with nothing over it,
/// one look at the location decides whether the route should leave from its other station. The route turns by itself
/// only when the answer is in before the trains can be read (by the moment the splash lifts on a cold start, within 1 s
/// on coming back); a later answer, one after a touch on Schedule, or one that may be on the train asks instead; after
/// 10 s the reader stops. A ride that ended at your stop turns the route with no reading. The rider's own choice wins:
/// a route chosen by hand is kept until the app has been out of view for more than 10 min, and Undo holds for an hour.
///
/// A visit is a cold start or a return from the background, until the next background. `ScheduleView` passes its `Scene`
/// on every change (`update(_:)`), its touches (`touched()`) and the background (`wentToBackground()`), and awaits
/// `cameBack(_:)` before its own arrival. Made in `RootView`; it never runs from the background or `AppDelegate`, and it
/// never asks for location.
@Observable
@MainActor
final class DirectionLook: RouteChoiceFollowing {
    /// What Schedule tells the look.
    struct Scene: Equatable {
        /// The scene is active.
        var isActive = false
        /// Schedule's tab is in front and no sheet of the app's is over it.
        var isInFront = false
        /// Something of Schedule's own is up: the station picker, the weather sheet, the Feedback sheet, the train
        /// question or the ride strip.
        var isBusy = false
        /// A bell's capsule or its day panel is up.
        var hasBellCapsule = false
        /// The launch splash still covers Schedule.
        var launchCovers = false

        /// Nothing is over Schedule.
        var isClear: Bool { isActive && isInFront && !isBusy && !hasBellCapsule }
    }

    /// The last look, for Settings › Testing: how long it waited and what it did. No place.
    struct LastLook: Equatable {
        let waited: TimeInterval
        let outcome: DirectionRule.Outcome
    }

    let capsule: DirectionCapsuleModel
    private(set) var lastLook: LastLook?
    /// A look is running: Schedule listens for a tap on itself meanwhile.
    private(set) var isLooking = false

    private let schedule: any RouteTurning
    private let location: any DirectionLocating
    private let stations: any StationRepository
    private let store: DirectionStore
    private let clock: any AppClock
    private let ride: (any DirectionRideSource)?
    private let offerDue: @MainActor () -> Bool
    private let track: @Sendable (Route, ServiceDay) async -> DirectionRule.Track?
    private let haptics: any HapticPlaying
    private let quick: Duration
    private let limit: Duration
    private let capsuleDelay: Duration
    private let playsSplash: Bool

    @ObservationIgnored private var scene = Scene()
    /// The visit is the cold start, not a return from the background.
    @ObservationIgnored private var isCold = true
    /// A route was saved when the visit began: the launch where the welcome sets the first route has no look.
    @ObservationIgnored private var hadRoute: Bool
    /// The next active scene begins a new visit.
    @ObservationIgnored private var beginsVisit = false
    /// This visit's look has run, or cannot run.
    @ObservationIgnored private var visitDone = false
    @ObservationIgnored private var run: Run?
    @ObservationIgnored private var runs = 0
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    /// The route the app turned to in this visit: the swap button back from it is the Undo.
    @ObservationIgnored private var turned: Route?
    @ObservationIgnored private var turnsMade = 0
    /// `turnsMade` when this visit began, until the visit's first `cameBack(_:)` has read it: a turn that Schedule's own
    /// `update(_:)` made before it (a ride's proof turns at once) is still that arrival's.
    @ObservationIgnored private var turnsBeforeVisit: Int?
    @ObservationIgnored private var usedArrival: RideArrival?
    /// A capsule that waits for the splash to lift.
    @ObservationIgnored private var pendingCapsule: DirectionCapsule.Kind?
    @ObservationIgnored private var capsuleTask: Task<Void, Never>?
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []

    /// A look in progress.
    private struct Run {
        let id: Int
        let route: Route
        /// Device time, for `LastLook.waited` only.
        let startedAt: Date
        /// The answer may still turn the route by itself.
        var mayTurn = true
        /// A cold start under the splash: `mayTurn` lasts until it lifts.
        var underSplash: Bool
        var ends: DirectionRule.Ends?
        var track: DirectionRule.Track?
        var reading: DirectionReading?
    }

    /// `track`: the track between the route's two stations for the train check, nil where there is none (fixture runs).
    /// `quick`, `limit` and `capsuleDelay` are the rule's times; tests shorten them. `playsSplash` is whether a cold start
    /// plays the launch splash: where it does not, a cold start follows the coming-back rule.
    init(
        schedule: any RouteTurning, location: any DirectionLocating, stations: any StationRepository, store: DirectionStore,
        clock: any AppClock, ride: (any DirectionRideSource)? = nil, offerDue: @escaping @MainActor () -> Bool = { false },
        track: @escaping @Sendable (Route, ServiceDay) async -> DirectionRule.Track? = { _, _ in nil },
        capsule: DirectionCapsuleModel = DirectionCapsuleModel(), haptics: any HapticPlaying = TTHaptics.shared,
        quick: Duration = DirectionRule.quick, limit: Duration = DirectionRule.limit,
        capsuleDelay: Duration = .milliseconds(1000), playsSplash: Bool = LaunchMotion.plays
    ) {
        self.schedule = schedule
        self.location = location
        self.stations = stations
        self.store = store
        self.clock = clock
        self.ride = ride
        self.offerDue = offerDue
        self.track = track
        self.capsule = capsule
        self.haptics = haptics
        self.quick = quick
        self.limit = limit
        self.capsuleDelay = capsuleDelay
        self.playsSplash = playsSplash
        hadRoute = schedule.route != nil
    }

    /// Automatic direction reads on: location allowed with Precise Location, unless the rider turned it off.
    var isOn: Bool { location.readsOn(store) }

    // MARK: Schedule's side

    /// Schedule's scene changed. Starts the visit's look once nothing is over Schedule on Today, lets a ride's proof turn
    /// the route, stops a look when the scene leaves active, and ends the direction capsule when a bell's takes the stage.
    func update(_ scene: Scene) {
        let lifted = self.scene.launchCovers && !scene.launchCovers
        self.scene = scene
        if scene.hasBellCapsule {
            capsuleTask?.cancel()
            pendingCapsule = nil
            capsule.dismiss()
        }
        if lifted {
            // The splash lifted: the trains can be read from here, so a later answer asks.
            if var run, run.underSplash {
                run.underSplash = false
                run.mayTurn = false
                self.run = run
                resumeWaiters()
            }
            if let kind = pendingCapsule {
                pendingCapsule = nil
                showSoon(kind)
            }
        }
        guard scene.isActive else {
            if run != nil { finish(.nothing(.left)) }
            return
        }
        if beginsVisit {
            beginsVisit = false
            hadRoute = schedule.route != nil
            turnsBeforeVisit = turnsMade
        }
        proveIfDue()
        startIfDue()
    }

    /// A drag or a tap on Schedule itself, or a day tapped: the rider is reading, so an answer from here on asks.
    func touched() {
        guard var run, run.mayTurn else { return }
        run.mayTurn = false
        run.underSplash = false
        self.run = run
        resumeWaiters()
    }

    /// The app went to the background: the visit is over. A running look is cancelled and the capsule goes.
    func wentToBackground() {
        store.leftView(at: clock.now)
        if run != nil { finish(.nothing(.left)) }
        capsuleTask?.cancel()
        pendingCapsule = nil
        capsule.dismiss()
        isCold = false
        beginsVisit = true
        visitDone = false
        turned = nil
    }

    /// Back in the app: `ScheduleViewModel.cameToForeground(looking:)` awaits this before its own arrival, 1 s at most, so
    /// there is one arrival and one Now play. True when the route turned, whose own load, jump and Now play are then the
    /// arrival's. The cold start does not wait: its look runs under the splash.
    func cameBack(_ scene: Scene) async -> Bool {
        let made = turnsMade
        update(scene)
        // Schedule's own `update(_:)` may have begun this visit first: a turn it made then is this arrival's too.
        let before = turnsBeforeVisit ?? made
        turnsBeforeVisit = nil
        if turnsMade != before { return true }
        guard !isCold, let run, run.mayTurn else { return false }
        await withCheckedContinuation { waiters.append($0) }
        return turnsMade != before
    }

    /// The Turned capsule's Undo: the route turns back, and not again between these two stations for an hour.
    func undo() async {
        guard case .turned = capsule.shown?.kind, let route = schedule.route else { return }
        haptics.play(.undo)
        turned = nil
        store.startUndoHour(for: route, at: clock.now)
        capsule.show(.kept)
        await schedule.turn()
    }

    /// The asking capsule's Switch: the route turns, with no capsule after.
    func switchRoute() async {
        guard case .asks = capsule.shown?.kind else { return }
        haptics.play(.swap)
        capsule.dismiss()
        await schedule.turn()
    }

    // MARK: The rider's choice

    func chose(_ route: Route, by choice: RouteChoice) {
        let now = clock.now
        switch choice {
        case .byHand:
            if run != nil { finish(.nothing(.chosenByHand)) }
            store.choseByHand(at: now)
            store.setMorningWay(from: route, at: now)
            capsuleTask?.cancel()
            pendingCapsule = nil
            if let turned, route.from.id == turned.to.id, route.to.id == turned.from.id {
                // The swap button back from a turn the app made is the Undo, once the capsule has gone and before.
                store.startUndoHour(for: route, at: now)
                capsule.show(.kept)
            } else {
                capsule.dismiss()
            }
            turned = nil
        case .trainLink:
            if run != nil { finish(.nothing(.chosenByLink)) }
            visitDone = true
            store.choseByHand(at: now)
            capsuleTask?.cancel()
            pendingCapsule = nil
            capsule.dismiss()
            turned = nil
        case .widgetRoute:
            // Applied before the look, which may turn it: a look that ran for the old route starts again, and Schedule's
            // arrival goes on waiting for the new one. What a finished look or a ride's proof said about the old route
            // goes with it (the capsule, and the turn the swap button would undo), and the new route gets its own look.
            let restarts = run != nil
            if restarts { finish(.nothing(.restarted), keepsWaiters: true) }
            capsuleTask?.cancel()
            pendingCapsule = nil
            capsule.dismiss()
            turned = nil
            visitDone = false
            startIfDue()
            if restarts, run == nil { resumeWaiters() }
        }
    }

    // MARK: The look

    /// A ride that ended at your stop is proof with no reading: once the ride's sheet is gone and Schedule shows, the
    /// route turns to leave from that stop, when it is the route's To, within an hour of the ride's end. The Undo hour
    /// stops it; a route chosen by hand does not. Detect my train's offer goes first.
    private func proveIfDue() {
        guard let arrival = ride?.arrival, arrival != usedArrival else { return }
        let now = clock.now
        guard now.timeIntervalSince(arrival.at) <= DirectionRule.proofLasts else {
            usedArrival = arrival
            return
        }
        guard scene.isClear, schedule.isToday, ride?.holdsRide != true, !offerDue(), let route = schedule.route else { return }
        usedArrival = arrival
        guard isOn, route.to.id == arrival.stopId, !store.holdsUndo(for: route, at: now) else { return }
        if run != nil { finish(.nothing(.rideProof)) }
        visitDone = true
        lastLook = LastLook(waited: 0, outcome: .turn)
        turn()
    }

    private func startIfDue() {
        guard run == nil, !visitDone, scene.isClear, schedule.isToday else { return }
        // Detect my train's offer goes first: the look waits for its sheet to close.
        guard !offerDue() else { return }
        visitDone = true
        let now = clock.now
        guard hadRoute, let route = schedule.route else { return note(.noRoute) }
        // Read right before each start; the look never asks.
        guard isOn else { return note(.off) }
        guard ride?.holdsRide != true else { return note(.riding) }
        guard !store.holdsChoice(at: now) else { return note(.chosenByHand) }
        guard !store.holdsUndo(for: route, at: now) else { return note(.undone) }
        start(route)
    }

    private func start(_ route: Route) {
        runs += 1
        let id = runs
        // Where no splash plays, a cold start follows the coming-back rule.
        let underSplash = isCold && playsSplash && scene.launchCovers
        run = Run(id: id, route: route, startedAt: Date(), underSplash: underSplash)
        isLooking = true
        let stations = stations
        let track = track
        let day = ServiceDay(containing: clock.now)
        tasks.append(
            Task { [weak self] in
                // The places come from the station list by id: a saved route carries none.
                let list = try? await stations.stations()
                guard let from = list?.first(where: { $0.id == route.from.id })?.place,
                    let to = list?.first(where: { $0.id == route.to.id })?.place
                else {
                    self?.finish(.nothing(.noPlaces), run: id)
                    return
                }
                let rails = await track(route, day)
                let ends = DirectionRule.Ends(fromId: route.from.id, from: from, toId: route.to.id, to: to)
                self?.ready(ends, track: rails, run: id)
            }
        )
        if !underSplash {
            let quick = quick
            tasks.append(
                Task { [weak self] in
                    try? await Task.sleep(for: quick)
                    guard !Task.isCancelled else { return }
                    self?.quickPassed(run: id)
                }
            )
        }
        let limit = limit
        tasks.append(
            Task { [weak self] in
                try? await Task.sleep(for: limit)
                guard !Task.isCancelled else { return }
                self?.finish(.nothing(.noReading), run: id)
            }
        )
        location.start { [weak self] reading in self?.read(reading, run: id) }
    }

    private func read(_ reading: DirectionReading, run id: Int) {
        guard var run, run.id == id else { return }
        run.reading = reading
        self.run = run
        decide()
    }

    private func ready(_ ends: DirectionRule.Ends, track: DirectionRule.Track?, run id: Int) {
        guard var run, run.id == id else { return }
        run.ends = ends
        run.track = track
        self.run = run
        decide()
    }

    private func quickPassed(run id: Int) {
        guard var run, run.id == id else { return }
        run.mayTurn = false
        self.run = run
        resumeWaiters()
    }

    /// The first reading that gives an answer decides; one that says nothing waits for the next.
    private func decide() {
        guard let run, let ends = run.ends, let reading = run.reading else { return }
        let verdict = DirectionRule.verdict(ends: ends, reading: reading, track: run.track)
        guard let outcome = DirectionRule.outcome(of: verdict, mayTurn: run.mayTurn) else { return }
        finish(outcome)
    }

    /// `keepsWaiters`: the look starts again at once, so `cameBack(_:)` goes on waiting.
    private func finish(_ outcome: DirectionRule.Outcome, run id: Int? = nil, keepsWaiters: Bool = false) {
        guard let run, id == nil || run.id == id else { return }
        self.run = nil
        isLooking = false
        tasks.forEach { $0.cancel() }
        tasks = []
        location.stop()
        var outcome = outcome
        // An answer that arrives while something is over Schedule, a bell's capsule is up, or the route or the day has
        // changed is dropped.
        if outcome == .turn || outcome == .ask, !scene.isClear || !schedule.isToday || schedule.route != run.route {
            outcome = .nothing(.covered)
        }
        lastLook = LastLook(waited: Date().timeIntervalSince(run.startedAt), outcome: outcome)
        switch outcome {
        case .turn:
            turn()
        case .ask:
            // Under the splash the question waits for the lift, as "Now from Union" does.
            let question = DirectionCapsule.Kind.asks(station: StationNames.short(run.route.to.name))
            if scene.launchCovers { pendingCapsule = question } else { capsule.show(question) }
        case .nothing:
            break
        }
        if !keepsWaiters { resumeWaiters() }
    }

    private func note(_ reason: DirectionRule.Reason) {
        lastLook = LastLook(waited: 0, outcome: .nothing(reason))
    }

    /// The route turns by itself: silent, then "Now from Union" 1000 ms later (after the splash has lifted).
    private func turn() {
        guard let route = schedule.route else { return }
        turnsMade += 1
        turned = Route(from: route.to, to: route.from, line: route.line)
        Task { [weak self] in await self?.schedule.turn() }
        showSoon(.turned(station: StationNames.short(route.to.name)))
    }

    private func showSoon(_ kind: DirectionCapsule.Kind) {
        guard !scene.launchCovers else {
            pendingCapsule = kind
            return
        }
        capsuleTask?.cancel()
        let delay = capsuleDelay
        capsuleTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.scene.isActive, !self.scene.hasBellCapsule else { return }
            self.capsule.show(kind)
        }
    }

    private func resumeWaiters() {
        let waiting = waiters
        waiters = []
        for waiter in waiting { waiter.resume() }
    }
}

extension EnvironmentValues {
    /// Automatic direction's look (TT-234, D116), from `RootView`; nil in previews and snapshots that draw Schedule alone.
    @Entry var directionLook: DirectionLook? = nil
}
