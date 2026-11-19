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

/// Who turns the route without the swap button (TT-235, D116).
enum RouteTurnKind: Sendable {
    /// The look, from the rider's place: at an open, on coming back, after a ride that ended at the stop.
    case byItself
    /// The asking capsule's Switch.
    case switched
    /// The Turned capsule's Undo: the route goes back, and the arrow on From goes.
    case undone
}

/// What the look needs from Schedule: its route, whether Today shows, and the silent turn.
@MainActor
protocol RouteTurning: AnyObject {
    var route: Route? { get }
    var isToday: Bool { get }
    /// Turns the route round with no haptic and no event (`ScheduleViewModel.turn(_:while:)`). The other direction's
    /// trains are read first, while the old ones show; `stillMay` is asked once they are in, right before the route turns
    /// in that same step, and false leaves everything as it is. False when nothing turned.
    func turn(_ kind: RouteTurnKind, while stillMay: @MainActor () -> Bool) async -> Bool
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
/// on coming back) and the other direction's trains are in by then too (TT-235: a turn never empties the timeline, so
/// they are read first and late trains count as a late answer); a later answer, one after a touch on Schedule, or one
/// that may be on the train asks instead; after 10 s the reader stops. A ride that ended at your stop turns the route
/// with no reading. The rider's own choice wins: a route chosen by hand is kept until the app has been out of view for
/// more than 10 min, and Undo holds for an hour.
///
/// Part 3 (TT-236): the first turn the app makes at an open or a return, or a first Switch, brings the one-time strip
/// (`showsStrip`, under the day strip in the ride strip's slot) until it is answered; "Now from …" shows on the app's first
/// 8 turns only (`DirectionRule.capsuleTurns`), and on every turn with Reduce Motion on.
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
        /// Reduce Motion is on: the names do not trade, so "Now from …" shows on every turn (TT-236).
        var reduceMotion = false

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
    /// The one-time strip is up (TT-236): "Automatic direction is on" with OK and Turn off, in the ride strip's slot,
    /// until it is answered. Kept for the run; the phone stores only whether it was answered.
    private(set) var showsStrip = false

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
    private let stripDelay: Duration
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
    /// The answer said turn and the other direction's trains are being read (TT-235): the route turns when they are in,
    /// unless the turn has become late by then.
    @ObservationIgnored private var turning: Turning?
    @ObservationIgnored private var turnings = 0
    @ObservationIgnored private var turningTimer: Task<Void, Never>?
    /// Detect my train's offer was shown in this visit: the strip waits for a later turn (TT-236).
    @ObservationIgnored private var offerShownThisVisit = false
    /// The strip, on its way in as the names land.
    @ObservationIgnored private var stripTask: Task<Void, Never>?

    /// A turn that waits for its trains.
    private struct Turning {
        let id: Int
        let route: Route
        /// Decided under the splash: the trains have until it lifts. Otherwise the rest of the 1 s.
        let underSplash: Bool
        /// A ride's proof: no strip with it (TT-236).
        let isProof: Bool
        /// Device time, for `LastLook.waited`.
        let startedAt: Date
    }

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
    /// `quick`, `limit` and `capsuleDelay` are the rule's times; tests shorten them. `stripDelay` is when the one-time strip
    /// comes after a turn that is not under the splash: as the names land (TT-236). `playsSplash` is whether a cold start
    /// plays the launch splash: where it does not, a cold start follows the coming-back rule.
    init(
        schedule: any RouteTurning, location: any DirectionLocating, stations: any StationRepository, store: DirectionStore,
        clock: any AppClock, ride: (any DirectionRideSource)? = nil, offerDue: @escaping @MainActor () -> Bool = { false },
        track: @escaping @Sendable (Route, ServiceDay) async -> DirectionRule.Track? = { _, _ in nil },
        capsule: DirectionCapsuleModel = DirectionCapsuleModel(), haptics: any HapticPlaying = TTHaptics.shared,
        quick: Duration = DirectionRule.quick, limit: Duration = DirectionRule.limit,
        capsuleDelay: Duration = .milliseconds(1000), stripDelay: Duration = .seconds(SwapMotion.restTime),
        playsSplash: Bool = LaunchMotion.plays
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
        self.stripDelay = stripDelay
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
            // The other direction's trains were not in by the lift: the launch plays as it is and the capsule asks.
            if let turning, turning.underSplash { turnIsLate(turning.id, afterLift: true) }
            if let kind = pendingCapsule {
                pendingCapsule = nil
                showSoon(kind)
            }
        }
        followSettingForStrip()
        guard scene.isActive else {
            if run != nil { finish(.nothing(.left)) }
            dropTurning()
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
        // The trains for a turn are still being read (a drag or a day tap; the read takes a moment only, so Schedule does
        // not listen for plain taps then): the rider is reading the old ones, so the capsule asks.
        if let turning { return turnIsLate(turning.id) }
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
        dropTurning()
        capsuleTask?.cancel()
        pendingCapsule = nil
        capsule.dismiss()
        isCold = false
        beginsVisit = true
        visitDone = false
        offerShownThisVisit = false
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
        // A look that may still turn, or a turn whose trains are being read.
        guard !isCold, run?.mayTurn == true || turning != nil else { return false }
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
        _ = await schedule.turn(.undone) { true }
    }

    /// The asking capsule's Switch: the route turns, with no capsule after.
    func switchRoute() async {
        guard case .asks = capsule.shown?.kind else { return }
        haptics.play(.swap)
        capsule.dismiss()
        // A first Switch brings the one-time strip; it is not counted (it shows no "Now from …"). It is offered in the step
        // the route turns in, so it lands with the names, not after the new trains' live status is read.
        _ = await schedule.turn(.switched, while: {
            offerStrip()
            return true
        })
    }

    // MARK: The one-time strip (TT-236)

    /// Detect my train's offer is shown (`RootView`): the strip does not show in this visit.
    func offerShown() {
        offerShownThisVisit = true
    }

    /// The strip's OK: it closes for good.
    func stripOK() {
        guard showsStrip else { return }
        haptics.play(.undo)
        answerStrip()
    }

    /// The strip's Turn off: only the setting goes off, as in Settings, with the same event; the route stays as it is, and
    /// Undo on the capsule or the swap button puts it back.
    func stripTurnOff() {
        guard showsStrip else { return }
        haptics.play(.undo)
        answerStrip()
        let was = isOn
        store.isOff = true
        // No property says where: a Turn off on the strip would say that a first turn just happened.
        if was { Analytics.track(.settingChanged("auto_direction", value: "off")) }
    }

    /// The rider turned the switch off in Settings: an unanswered strip goes and counts as answered.
    func turnedOffInSettings() {
        guard showsStrip || stripTask != nil else { return }
        answerStrip()
    }

    /// Puts the strip up as a first turn does, with no wait. A turn calls it through `offerStrip(now:)`; snapshots call
    /// it directly.
    func showStrip() {
        stripTask?.cancel()
        stripTask = nil
        if !showsStrip { showsStrip = true }
    }

    /// The strip comes with this turn unless it was answered, Automatic direction reads off, or Detect my train's offer is
    /// due or was shown in this visit (then it waits for a later turn). `now`: the turn was made under the splash, so the
    /// strip is in place when it lifts; otherwise it arrives as the names land.
    private func offerStrip(now: Bool = false) {
        guard !showsStrip, stripTask == nil, !store.stripAnswered, isOn, !offerDue(), !offerShownThisVisit else { return }
        guard !now, stripDelay > .zero else { return showStrip() }
        let delay = stripDelay
        stripTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.stripTask = nil
            guard !self.store.stripAnswered, self.isOn else { return }
            self.showsStrip = true
        }
    }

    /// The strip shows only while Automatic direction reads on. Turned off by the rider: it goes and counts as answered.
    /// Location no longer allowed (Allow Once ran out, refused, Precise Location off): it goes and keeps its first time.
    private func followSettingForStrip() {
        guard showsStrip || stripTask != nil, !isOn else { return }
        if store.isOff {
            answerStrip()
        } else {
            hideStrip()
        }
    }

    private func answerStrip() {
        store.stripAnswered = true
        hideStrip()
    }

    private func hideStrip() {
        stripTask?.cancel()
        stripTask = nil
        if showsStrip { showsStrip = false }
    }

    // MARK: The rider's choice

    func chose(_ route: Route, by choice: RouteChoice) {
        let now = clock.now
        switch choice {
        case .byHand:
            if run != nil { finish(.nothing(.chosenByHand)) }
            dropTurning()
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
            dropTurning()
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
            let restarts = run != nil || turning != nil
            if run != nil { finish(.nothing(.restarted), keepsWaiters: true) }
            dropTurning(keepsWaiters: true)
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
        dropTurning(keepsWaiters: true)
        visitDone = true
        lastLook = LastLook(waited: 0, outcome: .turn)
        turn(route, underSplash: playsSplash && scene.launchCovers, within: quick, startedAt: Date(), isProof: true)
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
        let waited = Date().timeIntervalSince(run.startedAt)
        lastLook = LastLook(waited: waited, outcome: outcome)
        switch outcome {
        case .turn:
            // The arrival goes on waiting until the trains are in and the route turns, or the turn is late.
            turn(run.route, underSplash: run.underSplash, within: quick - .seconds(waited), startedAt: run.startedAt)
            return
        case .ask:
            ask(run.route)
        case .nothing:
            break
        }
        if !keepsWaiters { resumeWaiters() }
    }

    /// "Trains from Union?" with Switch. Under the splash the question waits for the lift, as "Now from Union" does.
    private func ask(_ route: Route) {
        let question = DirectionCapsule.Kind.asks(station: StationNames.short(route.to.name))
        if scene.launchCovers { pendingCapsule = question } else { capsule.show(question) }
    }

    private func note(_ reason: DirectionRule.Reason) {
        lastLook = LastLook(waited: 0, outcome: .nothing(reason))
    }

    /// The route turns by itself (TT-235, D116). A turn never empties the timeline, so Schedule reads the other
    /// direction's trains first, while the old ones show, and the route turns in the step that puts them on screen:
    /// silent, then "Now from Union" 1000 ms later (after the splash has lifted). The trains have what is left of the
    /// time an answer has: until the splash lifts on a cold start (`underSplash`), `within` otherwise. Later than that,
    /// after a touch, or with no timetable to read, the answer counts as late: nothing moves and the capsule asks.
    private func turn(_ route: Route, underSplash: Bool, within: Duration, startedAt: Date, isProof: Bool = false) {
        turnings += 1
        let id = turnings
        turning = Turning(id: id, route: route, underSplash: underSplash, isProof: isProof, startedAt: startedAt)
        turningTimer?.cancel()
        turningTimer = nil
        if !underSplash {
            turningTimer = Task { [weak self] in
                try? await Task.sleep(for: within)
                guard !Task.isCancelled else { return }
                self?.turnIsLate(id)
            }
        }
        Task { [weak self] in
            guard let self else { return }
            let made = await self.schedule.turn(.byItself) { self.makesTurn(id) }
            // Not made with the turn still waiting: there was no timetable to read.
            if !made { self.turnIsLate(id) }
        }
    }

    /// Schedule has the other direction's trains and asks, right before it turns the route: yes while the turn still
    /// waits and Schedule is as the look found it. The turn is counted; "Now from …" follows on the first 8 (always with
    /// Reduce Motion), and the one-time strip with a first turn that is not a ride's proof (TT-236).
    private func makesTurn(_ id: Int) -> Bool {
        guard let turning, turning.id == id else { return false }
        let route = turning.route
        guard scene.isClear, schedule.isToday, schedule.route == route else {
            lastLook = LastLook(waited: Date().timeIntervalSince(turning.startedAt), outcome: .nothing(.covered))
            dropTurning()
            return false
        }
        turnsMade += 1
        turned = Route(from: route.to, to: route.from, line: route.line)
        dropTurning()
        let counted = store.turnsCounted
        store.countTurn()
        if counted < DirectionRule.capsuleTurns || scene.reduceMotion {
            showSoon(.turned(station: StationNames.short(route.to.name)))
        }
        // After a ride Allow Once may be gone by tomorrow: that turn keeps the strip's first time for the next one.
        if !turning.isProof { offerStrip(now: scene.launchCovers) }
        return true
    }

    /// The trains did not come in time: nothing moves, and the capsule asks (TT-234's ask) if Schedule is still as the
    /// look found it. `afterLift`: the splash has just lifted, and the question shows as one held under it does.
    private func turnIsLate(_ id: Int, afterLift: Bool = false) {
        guard let turning, turning.id == id else { return }
        let route = turning.route
        let stands = scene.isClear && schedule.isToday && schedule.route == route
        lastLook = LastLook(
            waited: Date().timeIntervalSince(turning.startedAt), outcome: stands ? .ask : .nothing(.covered)
        )
        dropTurning()
        guard stands else { return }
        if afterLift {
            showSoon(.asks(station: StationNames.short(route.to.name)))
        } else {
            ask(route)
        }
    }

    /// Ends a turn that waits for its trains: Schedule's question then gets a no. `keepsWaiters`: a look starts again
    /// at once, so `cameBack(_:)` goes on waiting.
    private func dropTurning(keepsWaiters: Bool = false) {
        guard turning != nil else { return }
        turning = nil
        turningTimer?.cancel()
        turningTimer = nil
        if !keepsWaiters { resumeWaiters() }
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
