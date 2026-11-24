import Foundation

/// One fix from a significant-change wake-up (TT-176): from cell towers, so coarse, and `speed` is negative when iOS gives
/// none.
struct WakeFix: Sendable, Equatable {
    let coordinate: GeoPoint
    /// Metres; a negative value means the fix is not valid.
    let horizontalAccuracy: Double
    /// Metres a second; negative when unknown.
    var speed: Double = -1
}

/// Location for "When the app is closed" (TT-243, D120; "Detect my train" before it, TT-176): the Always permission and the
/// significant-change wake-ups, which iOS sends at most every 5 minutes after about 500 m and which relaunch a stopped app.
/// `SystemWakeLocation` in the app, a fake in tests.
@MainActor
protocol WakeLocationProviding: AnyObject {
    /// Always is allowed. Reading it never asks.
    var allowsAlways: Bool { get }
    /// iOS has never asked for location, so `requestWhenInUse()` would show its prompt (TT-234, D116). Reading it never
    /// asks.
    var canAskWhenInUse: Bool { get }
    /// iOS can still show its Always dialog: it shows it once, so after that only the Settings app allows Always (TT-243).
    /// Reading it never asks.
    var canAskAlways: Bool { get }
    /// Shows the iOS When In Use prompt if the rider has not answered it yet; true when location is allowed after it.
    func requestWhenInUse() async -> Bool
    /// Shows the iOS Always dialog when iOS still can (it shows it once), and says whether Always is allowed after it.
    /// Where location was never asked, `requestWhenInUse()` goes first.
    func requestAlways() async -> Bool
    /// Starts the wake-ups; each one calls `onWake`.
    func startWakes(_ onWake: @escaping @MainActor (WakeFix) async -> Void)
    func stopWakes()
}

/// One of today's alerted trains as the app-closed tier sees it: the watch's candidate and the trip's plan with its track.
struct AutoRideTrain: Sendable {
    let candidate: AutoRideWatch.Candidate
    let plan: RidePlan
}

/// "When the app is closed" (TT-243, D120; board 47's "When it can run"): with the switch on and location Always allowed,
/// the automatic ride's watch is armed with the app closed, on a significant-change wake whose fix is within 300 m of an
/// alerted train's track or 1 km of its origin (counting a coarse fix's accuracy up to 1 km), or when the server's card for
/// an alerted train arrives with the app in the background; each only for a train whose window is open (L − 30 to L + 2
/// min). The watch then reads `BackgroundFixes` and accepts Y1's covered form at any station. A wake after an alerted
/// train's window, with no watch for it, arms nothing and counts `not_armed`. Today's alerted trains come from the stored
/// rules and the timetable (`AlertRules` lives only in `RootView`). Whether iOS launches the app for the card, and how soon
/// the wakes come, is unverified: `auto_ride_checked`'s `armed` says which way works. One per app, owned by `AppDelegate`,
/// `resume()` at every launch, which is how a relaunch for a wake-up reaches it; nil in fixture runs.
@MainActor
final class AutoRideWake {
    /// A wake this close to an alerted train's track, or to its origin, counting the fix's accuracy up to `accuracySlack`.
    static let lineReach = 300.0
    static let originReach = 1000.0
    static let accuracySlack = 1000.0

    /// What a wake-up or a card led to.
    enum Outcome: Equatable {
        /// The watch armed.
        case armed
        /// The switch is off, Always is not allowed, or Automatic ride is off.
        case off
        /// The app is in front (its own arming runs there), or a watch or a ride runs already.
        case busy
        /// No alerted train in its window near the fix, or a gate kept the one there from arming (`not_armed`).
        case nothing
        /// Near an alerted train whose window is over: `not_armed`.
        case late
    }

    private let location: any WakeLocationProviding
    private let watch: AutoRideWatch
    private let store: AutoRideStore
    private let clock: any AppClock
    private let trains: @MainActor (Date) async -> [AutoRideTrain]
    private let isInForeground: @MainActor () -> Bool
    private var isWaking = false

    /// `trains`: today's alerted trains at a moment, with their plans. `isInForeground`: the app is not in the background.
    init(
        location: any WakeLocationProviding,
        watch: AutoRideWatch,
        store: AutoRideStore,
        clock: any AppClock,
        trains: @escaping @MainActor (Date) async -> [AutoRideTrain],
        isInForeground: @escaping @MainActor () -> Bool = { false }
    ) {
        self.location = location
        self.watch = watch
        self.store = store
        self.clock = clock
        self.trains = trains
        self.isInForeground = isInForeground
    }

    /// When the app is closed reads on: the rider's own "on", Always allowed and Automatic ride not turned off.
    var isOn: Bool {
        store.closed && !store.isOff && location.allowsAlways
    }

    /// Always is allowed (Settings' switch reads on only with it).
    var allowsAlways: Bool { location.allowsAlways }

    /// iOS can still show its Always dialog; otherwise only the Settings app allows Always.
    var canAskAlways: Bool { location.canAskAlways }

    /// At launch, also when iOS relaunches the app for a wake-up, and after a change in Settings: the wake-ups run while it
    /// reads on, and stop otherwise.
    func resume() {
        if isOn {
            guard !isWaking else { return }
            isWaking = true
            location.startWakes { [weak self] fix in _ = await self?.wake(fix) }
        } else {
            isWaking = false
            location.stopWakes()
        }
    }

    /// The rider's "on", at once, before any prompt: with Always allowed it reads on now. True when it does.
    @discardableResult
    func switchOn() -> Bool {
        store.closed = true
        resume()
        return isOn
    }

    /// The rider's tap on When the app is closed: on at once, then When In Use first where location was never asked, and
    /// iOS's Always dialog where it still can (it shows it once). True when it reads on after.
    @discardableResult
    func turnOn() async -> Bool {
        store.closed = true
        if !location.allowsAlways {
            if location.canAskWhenInUse {
                guard await location.requestWhenInUse() else { return false }
            }
            guard location.canAskAlways, await location.requestAlways() else { return false }
        }
        resume()
        return isOn
    }

    /// Off: the wake-ups stop. A watch already armed with the app closed stops at its next look.
    func turnOff() {
        store.closed = false
        resume()
    }

    /// A significant-change wake-up.
    @discardableResult
    func wake(_ fix: WakeFix) async -> Outcome {
        guard isOn else {
            resume()
            return .off
        }
        guard !isInForeground(), watch.mayArm else { return .busy }
        guard fix.horizontalAccuracy >= 0 else { return .nothing }
        let now = clock.now
        let near = await trains(now).filter { Self.isNear(fix, $0.plan) }
        guard isOn, !isInForeground(), watch.mayArm else { return .busy }
        if let open = near.first(where: { watch.isInWindow($0.candidate, at: now) }) {
            return watch.armClosed(open.candidate, plan: open.plan, armed: .wake) ? .armed : .nothing
        }
        let late = near.filter { Self.isLate($0.candidate, at: now) }
        for train in late { watch.missed(train.candidate.ride, armed: .wake) }
        return late.isEmpty ? .nothing : .late
    }

    /// The server's card for `ride` arrived with the app in the background (board 47's "when the card arrives"): it comes
    /// at T−30, so the watch may read GPS for up to 40 min.
    @discardableResult
    func cardArrived(_ ride: Ride) async -> Outcome {
        guard isOn else { return .off }
        guard !isInForeground(), watch.mayArm else { return .busy }
        let now = clock.now
        guard let train = await trains(now).first(where: { $0.candidate.ride == ride }) else { return .nothing }
        guard isOn, !isInForeground(), watch.mayArm else { return .busy }
        guard watch.isInWindow(train.candidate, at: now) else { return .nothing }
        return watch.armClosed(train.candidate, plan: train.plan, armed: .card) ? .armed : .nothing
    }

    // MARK: Rules

    /// Within 300 m of the train's track or 1 km of its origin, counting a coarse fix's accuracy up to 1 km.
    static func isNear(_ fix: WakeFix, _ plan: RidePlan) -> Bool {
        guard fix.horizontalAccuracy >= 0 else { return false }
        let slack = min(fix.horizontalAccuracy, accuracySlack)
        if let origin = plan.stops.first?.station.place ?? plan.track.map({ $0.shape.point(at: $0.stopDistances[0]) }),
           TrackShape.distance(fix.coordinate, origin) <= originReach + slack {
            return true
        }
        guard let shape = plan.track?.shape else { return false }
        return shape.project(fix.coordinate).off <= lineReach + slack
    }

    /// The train's window is over and its question has not ended: a wake now came too late for it.
    static func isLate(_ candidate: AutoRideWatch.Candidate, at now: Date) -> Bool {
        let endsAt = min(candidate.departure.addingTimeInterval(LiveDeparture.askFor), max(candidate.arrival, candidate.departure))
        return now > candidate.departure.addingTimeInterval(AutoRideWatch.armTail) && now < endsAt
    }

    /// Today's alerted trains near `now`: for each switched-on alert, the trips it covers on today's service day between its
    /// stations, leaving within 90 min either side of `now`, with L from fresh live status when there is one, else the
    /// timetable, and the trip's plan; a trip with no plan is left out.
    static func alertedTrains(
        rules: [AlertRule], repository: any ScheduleRepository, departures: any AutoRideDepartureReading,
        plans: @MainActor (Ride) async -> RidePlan?, at now: Date
    ) async -> [AutoRideTrain] {
        let day = ServiceDay(containing: now)
        var trains: [AutoRideTrain] = []
        for rule in rules where !rule.paused {
            let route = Route(
                from: Station(id: rule.origin.id, name: rule.origin.name),
                to: Station(id: rule.destination.id, name: rule.destination.name),
                line: rule.line.isEmpty ? nil : Line(id: rule.line, name: "", colorHex: nil)
            )
            guard let trips = try? await repository.trips(for: route, on: day) else { continue }
            for trip in trips where rule.covers(trip, on: route) && abs(trip.scheduledDeparture.timeIntervalSince(now)) <= 90 * 60 {
                let ride = Ride(trip: trip.key, from: route.from.id, to: route.to.id)
                guard !trains.contains(where: { $0.candidate.ride == ride }), let plan = await plans(ride) else { continue }
                let candidate = await departures.departure(of: trip, ride: ride, at: now)
                    .map { AutoRideWatch.Candidate(route: route, departure: $0) }
                    ?? AutoRideWatch.Candidate(
                        route: route, trip: trip, departure: trip.scheduledDeparture, arrival: trip.scheduledArrival
                    )
                trains.append(AutoRideTrain(candidate: candidate, plan: plan))
            }
        }
        return trains
    }
}
