import Foundation
import Observation

// The wrong train warning (TT-250, D127): the phone left the rider's station with a train that will not take them to their
// stop. This part is the warning itself; nothing here detects (TT-251 raises it from its rule). Terms: T the rider's
// train (the ride's), O the station they get on at, D their stop, X the train they are really in.

/// Why X is wrong.
enum WrongTrainReason: String, Sendable {
    /// X goes the other way.
    case wrongWay = "wrong_way"
    /// X runs the same way and passes D without stopping.
    case skipsStop = "skips_stop"
    /// X is on another line.
    case otherLine = "other_line"
}

/// What told: GO's train positions, or only the track the phone follows.
enum WrongTrainEvidence: String, Sendable {
    case feed, track
}

/// How T's ride started: "I’m on board", the departure question's Yes, or no ride yet (an alerted train's card, TT-251).
/// Its own enum, since `alert` is not a `RideStartSource`.
enum WrongTrainSource: String, Sendable {
    case onBoard = "on_board"
    case departure
    case alert
}

/// Where the rider answered: the Live Activity card (the Lock Screen and the expanded island share its button), the ride
/// screen, Schedule's strip or the notification.
enum WrongTrainSurface: String, Sendable {
    case card, ride, schedule, notification
}

/// How the warning reached the rider: the app in front, the card with five buzzes, or the notification.
enum WrongTrainShown: String, Sendable {
    case app, card, notification
}

/// The first way a warning ended.
enum WrongTrainAnswer: String, Sendable {
    case fine, trains
    case endRide = "end_ride"
    case expired, withdrawn
}

/// One warning, as every screen reads it.
struct WrongTrainWarning: Equatable, Sendable {
    /// T's ride.
    let ride: Ride
    let reason: WrongTrainReason
    let evidence: WrongTrainEvidence
    let source: WrongTrainSource
    /// D as the ride's kicker names it, "Clarkson".
    let stopName: String
    /// O.
    let originId: String
    /// X's next stop, "OA" and "Oakville", and when X is expected there; nil when only the track told ("Next station …").
    let nextStopId: String
    let nextStopName: String
    let nextStopTime: Date?
    /// With no answer by then the ride and its card end, on the raising engine's clock.
    let expires: Date
    /// Whole seconds from the first moving fix to the warning; 0 on the demo.
    let secondsAfter: Int
    /// Settings › Testing's demo ride.
    let isDemo: Bool

    /// "Doesn’t stop at Clarkson", "Going away from Clarkson".
    var reasonLine: String {
        let key: String.LocalizationValue = reason == .wrongWay ? "wrong.why.away" : "wrong.why.skips"
        return String(format: String(localized: key), stopName)
    }

    /// "Next stop Oakville · 5:38 PM", or "Next station Oakville" with no time.
    func nextLine(formatter: some TimeFormatting) -> String {
        guard let nextStopTime else { return String(format: String(localized: "wrong.next.station"), nextStopName) }
        return String(format: String(localized: "wrong.next"), nextStopName, formatter.time(nextStopTime))
    }

    /// "Trains from Oakville".
    var trainsTitle: String {
        String(format: String(localized: "wrong.trains"), nextStopName)
    }

    /// The notification's body and the card alerts' line: "Doesn’t stop at Clarkson. Next stop Oakville, 5:38 PM."
    func notificationBody(formatter: some TimeFormatting) -> String {
        guard let nextStopTime else {
            return String(format: String(localized: "wrong.notif.body.station"), reasonLine, nextStopName)
        }
        return String(format: String(localized: "wrong.notif.body"), reasonLine, nextStopName, formatter.time(nextStopTime))
    }

    /// The card's state for beat `beat` of the five.
    func card(formatter: some TimeFormatting, beat: Int) -> RideActivityAttributes.ContentState.Wrong {
        RideActivityAttributes.ContentState.Wrong(
            reason: reasonLine, stop: stopName, next: nextLine(formatter: formatter), nextStop: nextStopName, beat: beat
        )
    }
}

/// The words the ride screen and Schedule's strip show (`RideDetails.wrongTrain`, `RideStripView`).
struct WrongTrainDisplay: Equatable, Sendable {
    /// "Doesn’t stop at Clarkson".
    let reason: String
    /// "Next stop Oakville · 5:38 PM", with `nextStop` set semibold in it.
    let next: String
    let nextStop: String
    /// "Trains from Oakville".
    let trains: String

    init(_ warning: WrongTrainWarning, formatter: some TimeFormatting) {
        reason = warning.reasonLine
        next = warning.nextLine(formatter: formatter)
        nextStop = warning.nextStopName
        trains = warning.trainsTitle
    }
}

/// "Trains from Oakville": Schedule turns to the way back from X's next stop (`RootView`, `WrongTrainRoute`).
struct WrongTrainRouteRequest: Equatable, Sendable {
    let nextStopId: String
    /// D.
    let stopId: String
    /// O.
    let originId: String
    /// Two taps make two requests.
    let id = UUID()
}

/// The words of the card's five alerts: "Wrong train?" and the notification's body.
struct WrongTrainAlert: Equatable, Sendable {
    let title: String
    let body: String
}

/// The notification posted when the app is not in front and no card can show (`WrongTrainNotice`).
struct WrongTrainNote: Equatable, Sendable {
    let ride: Ride
    let title: String
    let body: String
    /// The first action's title, "Trains from Oakville".
    let trainsTitle: String
    let nextStopId: String
    let originId: String
}

/// The warning on the Live Activity card (`RideLiveActivity`).
@MainActor
protocol WrongTrainShowing: AnyObject {
    /// Puts `wrong` on `ride`'s card (nil takes it away), alerting with `alert`; false when no showing card is that ride's or
    /// Live Activities are off. `until`: the card's stale date while it warns (TT-251's departure card); nil keeps its own.
    func show(
        _ wrong: RideActivityAttributes.ContentState.Wrong?, for ride: Ride, until: Date?, alert: WrongTrainAlert?
    ) async -> Bool
}

/// The warning's notification (`SystemWrongTrainNotifier`; a fake in tests, nil in fixture runs).
@MainActor
protocol WrongTrainNotifying: AnyObject {
    func post(_ note: WrongTrainNote) async
    func remove()
}

/// Background time while the demo plays (`beginBackgroundTask`): the demo ride has no location session, so a locked phone
/// would suspend the app before the five buzzes.
@MainActor
protocol BackgroundTiming: AnyObject {
    func begin()
    func end()
}

/// Today's trains the rider answered "I’m fine" for (trip id and service date), cleared when the day changes, as
/// `DetectionStore` does. No place, no X.
struct WrongTrainStore {
    static let key = "wrongTrain.fine"
    let defaults: UserDefaults?

    func isFine(_ ride: Ride) -> Bool {
        guard let defaults else { return false }
        return (defaults.stringArray(forKey: Self.key) ?? []).contains(Self.entry(ride))
    }

    func storeFine(_ ride: Ride) {
        guard let defaults else { return }
        let kept = (defaults.stringArray(forKey: Self.key) ?? []).filter { entry in
            entry.split(separator: "/", maxSplits: 1).first.flatMap { Int($0) }.map { $0 >= ride.serviceDate } ?? false
        }
        defaults.set(Array(Set(kept + [Self.entry(ride)])).sorted(), forKey: Self.key)
    }

    private static func entry(_ ride: Ride) -> String { "\(ride.serviceDate)/\(ride.tripId)" }
}

/// The route "Trains from Oakville" shows: from X's next stop to D when a train between them still leaves today (on the
/// clock Schedule shows), else back to O. Nil when a station is not in the schedule. Never the saved route as a fallback.
enum WrongTrainRoute {
    static func route(
        for request: WrongTrainRouteRequest, stations: any StationRepository, repository: any ScheduleRepository, now: Date
    ) async -> Route? {
        guard let all = try? await stations.stations(),
              let next = all.first(where: { $0.id == request.nextStopId }) else { return nil }
        if let stop = all.first(where: { $0.id == request.stopId }),
           let toStop = try? await stations.route(from: next, to: stop),
           let trips = try? await repository.trips(for: toStop, on: ServiceDay(containing: now)),
           trips.contains(where: { $0.scheduledDeparture > now }) {
            return toStop
        }
        guard let origin = all.first(where: { $0.id == request.originId }) else { return nil }
        return try? await stations.route(from: next, to: origin)
    }
}

/// The warning's presenter (TT-250, D127): one per app as `AppDelegate.wrongTrain`, made in every run, and the one thing
/// TT-251 calls (`raise(_:now:rate:)`, `withdraw()`). It decides how the warning reaches the rider (the app in front: Alarm
/// once; locked with a card: five alerting card updates `gap` apart; no card: the notification), keeps it until an answer,
/// its expiry or the end of its ride, and reports each to analytics. A warning lives in memory only.
@Observable @MainActor
final class WrongTrain {
    /// The card's alerts while the app is not in front.
    static let buzzes = 5
    /// 1.5 s between them; if fewer than five are felt, the next tries are 2 s, then fewer buzzes (D127).
    static let defaultGap: Duration = .milliseconds(1500)

    /// What every screen reads.
    private(set) var warning: WrongTrainWarning?
    /// "Trains from …" was tapped: `RootView` shows the route, then calls `routeHandled(_:)`.
    private(set) var routeRequest: WrongTrainRouteRequest?
    /// A tap on the warning's notification: `RootView` opens the app on the warning.
    private(set) var openRequest = 0

    /// Ends T's ride for "Trains from …" and the expiry: `RootView` sets it on the `OnBoard` it keeps (the demo's ride
    /// ends on the demo engine); tests set it. Unset (a cold launch), the app's engine ends it. True when a ride ended.
    @ObservationIgnored var endRide: (@MainActor (Ride) -> Bool)?

    private let card: (any WrongTrainShowing)?
    private let notifier: (any WrongTrainNotifying)?
    private let store: WrongTrainStore
    private let haptics: any HapticPlaying
    private let isActive: @MainActor () -> Bool
    private let gap: Duration
    private let clock: any AppClock
    private let formatter: @MainActor () -> TimeFormatter
    private let background: (any BackgroundTiming)?

    /// The app's engine, followed from launch (`follow(_:)`): its ride ending ends its warning.
    @ObservationIgnored private weak var appEngine: RideEngine?
    @ObservationIgnored private var appFollowing: Task<Void, Never>?
    @ObservationIgnored private var demoFollowing: Task<Void, Never>?
    /// Each warning's number, so a late beat or expiry of an earlier one does nothing.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var raisedAt: Date?
    @ObservationIgnored private var presenting: Task<Void, Never>?
    @ObservationIgnored private var expiry: Task<Void, Never>?
    /// The demo's "I’m fine", for its ride only: every demo ride of a day is the same `Ride`, so it is never stored.
    @ObservationIgnored private var demoFine = false
    @ObservationIgnored private var keepsAwake = false

    init(
        card: (any WrongTrainShowing)?,
        notifier: (any WrongTrainNotifying)?,
        store: WrongTrainStore,
        haptics: any HapticPlaying,
        isActive: @escaping @MainActor () -> Bool,
        gap: Duration = WrongTrain.defaultGap,
        clock: any AppClock = SystemClock(),
        formatter: @escaping @MainActor () -> TimeFormatter = { TimeFormatter(format: .device) },
        background: (any BackgroundTiming)? = nil
    ) {
        self.card = card
        self.notifier = notifier
        self.store = store
        self.haptics = haptics
        self.isActive = isActive
        self.gap = gap
        self.clock = clock
        self.formatter = formatter
        self.background = background
    }

    // MARK: Raising (TT-251's seam)

    /// Raises `warning`. `now`: the raising engine's time; `rate`: its ride seconds per real second (`DemoRide.speed` for the
    /// demo). Nothing if one already shows or the rider said "I’m fine" about that train today. Returns the task that shows
    /// it (tests await it).
    @discardableResult
    func raise(_ warning: WrongTrainWarning, now: Date, rate: Double = 1) -> Task<Void, Never>? {
        guard self.warning == nil, !isFine(warning) else { return nil }
        generation += 1
        let id = generation
        self.warning = warning
        raisedAt = clock.now
        let wait = max(0, warning.expires.timeIntervalSince(now)) / max(rate, 0.001)
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.expire(id)
        }
        let task = Task { [weak self] in await self?.present(warning, id: id) }
        presenting = task
        return task
    }

    /// Takes the warning away silently; the ride carries on.
    func withdraw() {
        guard warning != nil else { return }
        finish(.withdrawn)
    }

    // MARK: Answers

    /// "I’m fine" in the app: the warning goes, the card is the ride's own again, the ride carries on and the train is not
    /// warned about again today. The tapping screen plays Tap.
    func fine(surface: WrongTrainSurface) {
        guard let warning else { return }
        rememberFine(warning.ride, isDemo: warning.isDemo)
        finish(.fine, surface: surface)
    }

    /// "I’m fine" from the card's intent or the notification's action, by the train's ids. With no warning held (a cold
    /// launch) the train is stored and the answer counted.
    func fine(for ride: Ride, surface: WrongTrainSurface) {
        if let warning, warning.ride == ride {
            fine(surface: surface)
            return
        }
        let isDemo = ride.tripId == DemoRide.tripId
        rememberFine(ride, isDemo: isDemo)
        Analytics.track(.wrongTrainAnswered(.fine, surface: surface, seconds: 0, demo: isDemo))
    }

    /// "Trains from …": the ride ends (`wrong_train`), the warning and the notification go, and Schedule turns to the way
    /// back (`routeRequest`).
    func trains(surface: WrongTrainSurface) {
        guard let warning else { return }
        finish(.trains, surface: surface)
        end(warning.ride)
        routeRequest = WrongTrainRouteRequest(
            nextStopId: warning.nextStopId, stopId: warning.ride.destinationId, originId: warning.originId
        )
    }

    /// "Trains from …" on the notification by the train's ids. With no warning held (a cold launch, before the ride's
    /// restore) the app's running or saved ride ends when it is that train, and the route comes from the three stations.
    func trains(for ride: Ride, nextStopId: String, originId: String, surface: WrongTrainSurface) {
        if let warning, warning.ride == ride {
            trains(surface: surface)
            return
        }
        let isDemo = ride.tripId == DemoRide.tripId
        if !isDemo, let appEngine, appEngine.ride == nil || appEngine.ride == ride {
            appEngine.end(.wrongTrain)
        }
        Analytics.track(.wrongTrainAnswered(.trains, surface: surface, seconds: 0, demo: isDemo))
        routeRequest = WrongTrainRouteRequest(nextStopId: nextStopId, stopId: ride.destinationId, originId: originId)
    }

    /// End ride (or Done) while the warning shows (`OnBoard.end()`, before the engine ends).
    func endedByRider(_ ride: Ride?) {
        guard let warning, let ride, warning.ride == ride else { return }
        finish(.endRide)
    }

    /// A tap on the warning's notification.
    func openWarning() {
        openRequest += 1
    }

    /// `RootView` showed the route.
    func routeHandled(_ request: WrongTrainRouteRequest) {
        if routeRequest == request { routeRequest = nil }
    }

    // MARK: Following rides

    /// The app's engine, from launch: its ride ending (arrived, cancelled, left the line) takes its warning away.
    func follow(_ engine: RideEngine) {
        appEngine = engine
        appFollowing?.cancel()
        appFollowing = following(engine, isDemo: false)
    }

    /// A demo ride started (`OnBoard`): its "I’m fine" is forgotten, so this ride warns again, and its ending takes its
    /// warning away.
    func followDemo(_ engine: RideEngine) {
        demoFine = false
        demoFollowing?.cancel()
        demoFollowing = following(engine, isDemo: true)
    }

    /// The demo stopped: a demo warning goes.
    func demoEnded() {
        demoFollowing?.cancel()
        demoFollowing = nil
        if warning?.isDemo == true { finish(.withdrawn) }
        releaseAwake()
    }

    /// Background time from the demo ride's start until its fifth buzz (or its end).
    func keepAwake() {
        guard !keepsAwake else { return }
        keepsAwake = true
        background?.begin()
    }

    func releaseAwake() {
        guard keepsAwake else { return }
        keepsAwake = false
        background?.end()
    }

    private func following(_ engine: RideEngine, isDemo: Bool) -> Task<Void, Never> {
        let events = engine.events()
        return Task { [weak self, weak engine] in
            for await event in events {
                guard !Task.isCancelled else { return }
                guard case .phase(.ended) = event else { continue }
                guard let self, let warning = self.warning, warning.isDemo == isDemo else { continue }
                if !isDemo, let ride = engine?.ride, ride != warning.ride { continue }
                self.finish(.withdrawn)
            }
        }
    }

    // MARK: Showing

    private func present(_ warning: WrongTrainWarning, id: Int) async {
        let formatter = self.formatter()
        if isActive() {
            // In front: the app shows the warning, Alarm plays once, the card changes with no alert.
            haptics.play(.wrongTrain)
            Analytics.track(.wrongTrainWarned(warning, shown: .app))
            _ = await card?.show(warning.card(formatter: formatter, beat: 1), for: warning.ride, until: nil, alert: nil)
            settle(warning.ride, id: id)
            releaseAwake()
            return
        }
        let alert = WrongTrainAlert(title: String(localized: "wrong.title"), body: warning.notificationBody(formatter: formatter))
        let shows = await card?.show(warning.card(formatter: formatter, beat: 1), for: warning.ride, until: nil, alert: alert) ?? false
        guard isCurrent(id) else {
            settle(warning.ride, id: id)
            return
        }
        if shows {
            Analytics.track(.wrongTrainWarned(warning, shown: .card))
            for beat in 2...Self.buzzes {
                try? await Task.sleep(for: gap)
                guard !Task.isCancelled, isCurrent(id) else { break }
                _ = await card?.show(warning.card(formatter: formatter, beat: beat), for: warning.ride, until: nil, alert: alert)
            }
            settle(warning.ride, id: id)
        } else {
            Analytics.track(.wrongTrainWarned(warning, shown: .notification))
            await notifier?.post(WrongTrainNote(
                ride: warning.ride, title: String(localized: "wrong.title"), body: warning.notificationBody(formatter: formatter),
                trainsTitle: warning.trainsTitle, nextStopId: warning.nextStopId, originId: warning.originId
            ))
            // Answered while it was being posted: it goes again.
            if !isCurrent(id) { notifier?.remove() }
        }
        releaseAwake()
    }

    /// The warning was answered while a card update was in flight: that update may land after the one that cleared it, so
    /// the card is cleared once more.
    private func settle(_ ride: Ride, id: Int) {
        guard !isCurrent(id), warning == nil else { return }
        Task { _ = await card?.show(nil, for: ride, until: nil, alert: nil) }
    }

    private func isCurrent(_ id: Int) -> Bool {
        generation == id && warning != nil
    }

    // MARK: Ending

    private func expire(_ id: Int) {
        guard isCurrent(id), let warning else { return }
        finish(.expired)
        end(warning.ride)
    }

    /// The warning goes: the beats still to come stop, the card is the ride's own again, the notification goes, and the
    /// first answer is counted.
    private func finish(_ answer: WrongTrainAnswer, surface: WrongTrainSurface? = nil) {
        guard let warning else { return }
        self.warning = nil
        generation += 1
        presenting?.cancel()
        presenting = nil
        expiry?.cancel()
        expiry = nil
        let seconds = raisedAt.map { max(0, Int(clock.now.timeIntervalSince($0))) } ?? 0
        raisedAt = nil
        Task { _ = await card?.show(nil, for: warning.ride, until: nil, alert: nil) }
        notifier?.remove()
        releaseAwake()
        Analytics.track(.wrongTrainAnswered(answer, surface: surface, seconds: seconds, demo: warning.isDemo))
    }

    private func end(_ ride: Ride) {
        if let endRide {
            _ = endRide(ride)
            return
        }
        guard ride.tripId != DemoRide.tripId, let appEngine, appEngine.ride == ride else { return }
        appEngine.end(.wrongTrain)
    }

    private func isFine(_ warning: WrongTrainWarning) -> Bool {
        warning.isDemo ? demoFine : store.isFine(warning.ride)
    }

    private func rememberFine(_ ride: Ride, isDemo: Bool) {
        if isDemo {
            demoFine = true
        } else {
            store.storeFine(ride)
        }
    }
}
