import Foundation
import Observation

/// One fix from a significant-change wake-up (TT-176): from cell towers, so coarse, and `speed` is negative when iOS gives
/// none.
struct WakeFix: Sendable, Equatable {
    let coordinate: GeoPoint
    /// Metres; a negative value means the fix is not valid.
    let horizontalAccuracy: Double
    /// Metres a second; negative when unknown.
    var speed: Double = -1
}

/// Location for "Detect my train" (TT-176): the Always permission and the significant-change wake-ups, which iOS sends at
/// most every 5 minutes after about 500 m and which relaunch a stopped app. `SystemWakeLocation` in the app, a fake in
/// tests.
@MainActor
protocol WakeLocationProviding: AnyObject {
    /// Always is allowed. Reading it never asks.
    var allowsAlways: Bool { get }
    /// Shows the iOS Always dialog when iOS still can (it shows it once), and says whether Always is allowed after it.
    func requestAlways() async -> Bool
    /// Starts the wake-ups; each one calls `onWake`.
    func startWakes(_ onWake: @escaping @MainActor (WakeFix) async -> Void)
    func stopWakes()
}

/// Posts the background question as a notification, replacing an earlier one (`SystemDetectionNotifier`; a fake in tests).
@MainActor
protocol DetectionNotifying: AnyObject {
    func post(_ question: TrainMatcher.Question)
}

/// The train a background question asked about, as its notification carries it (TT-176): Start On board rides it, Not me
/// silences it, and every train that fitted with it, for its service day.
struct DetectedTrain: Hashable, Sendable {
    static let tripKey = "detect.tripId"
    static let serviceDateKey = "detect.serviceDate"
    static let originKey = "detect.originId"
    static let destinationKey = "detect.destinationId"
    static let fittingKey = "detect.fitting"

    let trip: TripKey
    /// The stretch of the route it was matched on: the ride's two stations.
    let originId: String
    let destinationId: String
    /// The trips that fitted when it was asked, on the same service day; the asked train among them.
    let fitting: [String]

    var ride: Ride { Ride(trip: trip, from: originId, to: destinationId) }

    /// The trains Not me silences for the day.
    var silenced: [TripKey] {
        Array(Set(fitting + [trip.tripId])).sorted().map { TripKey(serviceDay: trip.serviceDay, tripId: $0) }
    }

    init(trip: TripKey, originId: String, destinationId: String, fitting: [String] = []) {
        self.trip = trip
        self.originId = originId
        self.destinationId = destinationId
        self.fitting = fitting
    }

    /// The question's first train, the one that fits best.
    init?(_ question: TrainMatcher.Question) {
        guard let train = question.trains.first else { return nil }
        let offered = question.trains.map(\.trip) + question.fitting
        self.init(
            trip: train.trip, originId: train.route.from.id, destinationId: train.route.to.id,
            fitting: offered.filter { $0.serviceDay == train.trip.serviceDay }.map(\.tripId)
        )
    }

    /// From the notification; nil for any other notification.
    init?(userInfo: [AnyHashable: Any]) {
        guard let tripId = userInfo[Self.tripKey] as? String, !tripId.isEmpty,
              let date = (userInfo[Self.serviceDateKey] as? Int) ?? (userInfo[Self.serviceDateKey] as? String).flatMap(Int.init),
              let origin = userInfo[Self.originKey] as? String, let destination = userInfo[Self.destinationKey] as? String
        else { return nil }
        self.init(
            trip: TripKey(serviceDay: ServiceDay(dateKey: date), tripId: tripId), originId: origin, destinationId: destination,
            fitting: userInfo[Self.fittingKey] as? [String] ?? []
        )
    }

    var userInfo: [String: Any] {
        [
            Self.tripKey: trip.tripId,
            Self.serviceDateKey: trip.serviceDay.dateKey,
            Self.originKey: originId,
            Self.destinationKey: destinationId,
            Self.fittingKey: fitting,
        ]
    }
}

/// What "Detect my train" keeps on device (TT-176), readable from any thread: the notification's Not me is handled outside
/// the main actor, before iOS suspends the app again.
enum DetectionStore {
    /// The switch; off by default.
    static let enabledKey = "detect.background"
    /// The offer after the first completed ride was shown.
    static let offeredKey = "detect.offered"
    /// A ride reached its stop and the offer has not been shown yet.
    static let offerDueKey = "detect.offerDue"
    /// When each Not me was tapped, seconds since 1970.
    static let notMeKey = "detect.notMe"
    /// Three Not me in a week turned the switch off; Settings says so until it is turned on again.
    static let turnedOffKey = "detect.turnedOff"
    /// The trains not to ask about again today (TT-175's No): "20261127/tripId".
    static let silencedKey = "detect.silenced"

    /// Not me: its trains join today's silenced ones, and the tap is counted.
    static func recordNotMe(_ train: DetectedTrain, in defaults: UserDefaults, at now: Date) {
        silence(train.silenced, in: defaults)
        defaults.set(notMes(in: defaults) + [now.timeIntervalSince1970], forKey: notMeKey)
    }

    /// Adds trains to the silenced ones, keeping only today's, as `TrainDetector` reads them.
    static func silence(_ trips: [TripKey], in defaults: UserDefaults) {
        let stored = defaults.stringArray(forKey: silencedKey) ?? []
        let added = trips.map { "\($0.serviceDay.dateKey)/\($0.tripId)" }
        defaults.set(Array(Set(stored + added)).sorted(), forKey: silencedKey)
    }

    static func notMes(in defaults: UserDefaults) -> [TimeInterval] {
        defaults.array(forKey: notMeKey) as? [TimeInterval] ?? []
    }
}

/// "Detect my train" (TT-176, Live-Spec "Three doors into a ride", the third, and "When it runs"): opt-in, Always. While the
/// switch is on, iOS wakes the app on significant location changes. On a wake-up between 5 AM and 1 AM, with the phone
/// moving within 300 m of the track of a train on the saved route (either way, as Schedule's detection, D68), GPS runs the
/// matcher for up to 12 minutes; otherwise the app sleeps again. A match posts "On the 5:13 PM train?" with Start On board
/// (which opens the app; the ride and its Live Activity start once it is in front) and Not me (the train is not asked about
/// again today; three in a week turn the switch off). It never starts a ride by itself. One per app, made by `AppDelegate`.
@Observable @MainActor
final class BackgroundDetection {
    /// GPS stays on this long after a wake-up at most.
    static let checkDuration: TimeInterval = 12 * 60
    /// A wake-up this close to the track of a train on the route, counting the fix's accuracy up to `accuracySlack`.
    static let lineReach = TrainMatcher.lineReach
    static let accuracySlack = 1000.0
    /// Toronto hours with no checks, 1 AM to 5 AM; a check running at 1 AM stops then.
    static let quietHours = 1..<5
    static let notMeLimit = 3
    static let notMeWindow: TimeInterval = 7 * 24 * 3600

    /// What a wake-up led to.
    enum Wake: Equatable {
        /// GPS on for up to 12 minutes.
        case check
        /// The switch is off, or Always is not allowed.
        case off
        case quietHours
        /// A ride or a check runs already, or the app is in front, where Schedule's own detection runs (D68).
        case busy
        /// No route saved yet.
        case noRoute
        /// Standing still.
        case standing
        /// No train on the route runs within 300 m.
        case awayFromLine
    }

    /// The switch in Settings › Notifications.
    private(set) var isOn: Bool
    /// Three Not me in a week turned the switch off.
    private(set) var wasTurnedOff: Bool
    /// A ride reached its stop and the offer has not been shown: RootView shows it once Schedule is in front.
    private(set) var offerDue: Bool
    /// GPS is on for a check.
    private(set) var isChecking = false

    private let location: any WakeLocationProviding
    private let candidates: any TrainCandidatesProviding
    private let notifier: any DetectionNotifying
    private let clock: any AppClock
    private let defaults: UserDefaults
    private let route: @MainActor () -> Route?
    private let isRiding: @MainActor () -> Bool
    private let isInForeground: @MainActor () -> Bool
    private let makeDetector: @MainActor () -> TrainDetector
    private let tickInterval: Duration?
    @ObservationIgnored private var offered: Bool
    @ObservationIgnored private var detector: TrainDetector?
    @ObservationIgnored private var deadline: Date?
    @ObservationIgnored private var loop: Task<Void, Never>?

    /// `tickInterval` nil runs no timer: tests call `tick()`. `makeDetector` makes each check's matcher, on the GPS that
    /// runs in the background. `isInForeground` is true while the app is not in the background (in front, or inactive at
    /// launch or under a system dialog): a wake-up then, also the cached one iOS sends when the wake-ups start, checks
    /// nothing.
    init(
        location: any WakeLocationProviding,
        candidates: any TrainCandidatesProviding,
        notifier: any DetectionNotifying,
        clock: any AppClock,
        defaults: UserDefaults,
        route: @escaping @MainActor () -> Route?,
        isRiding: @escaping @MainActor () -> Bool,
        isInForeground: @escaping @MainActor () -> Bool = { false },
        makeDetector: @escaping @MainActor () -> TrainDetector,
        tickInterval: Duration? = .seconds(1)
    ) {
        self.location = location
        self.candidates = candidates
        self.notifier = notifier
        self.clock = clock
        self.defaults = defaults
        self.route = route
        self.isRiding = isRiding
        self.isInForeground = isInForeground
        self.makeDetector = makeDetector
        self.tickInterval = tickInterval
        isOn = defaults.bool(forKey: DetectionStore.enabledKey)
        wasTurnedOff = defaults.bool(forKey: DetectionStore.turnedOffKey)
        offered = defaults.bool(forKey: DetectionStore.offeredKey)
        offerDue = defaults.bool(forKey: DetectionStore.offerDueKey)
    }

    // MARK: The switch

    /// At launch, also when iOS relaunches the app for a wake-up (which arrives once the wake-ups start again): they start
    /// again while the switch is on and Always is still allowed; without Always the switch goes off.
    func resume() {
        refresh()
        guard isOn else { return }
        guard location.allowsAlways else { return turnOff() }
        startWakes()
    }

    /// Reads the Not me's again (one may have been tapped while the app was in the background): the third in a week turns
    /// the switch off.
    func refresh() {
        let now = clock.now
        let recent = DetectionStore.notMes(in: defaults).filter {
            now.timeIntervalSince(Date(timeIntervalSince1970: $0)) < Self.notMeWindow
        }
        defaults.set(recent, forKey: DetectionStore.notMeKey)
        guard isOn, recent.count >= Self.notMeLimit else { return }
        defaults.removeObject(forKey: DetectionStore.notMeKey)
        wasTurnedOff = true
        defaults.set(true, forKey: DetectionStore.turnedOffKey)
        turnOff()
    }

    /// Turn on, on the offer or the switch: on at once, then iOS asks for Always (once); off again when Always is not
    /// allowed. True when it stays on.
    @discardableResult
    func turnOn() async -> Bool {
        wasTurnedOff = false
        defaults.removeObject(forKey: DetectionStore.turnedOffKey)
        defaults.removeObject(forKey: DetectionStore.notMeKey)
        setOn(true)
        guard await location.requestAlways(), isOn else {
            setOn(false)
            return false
        }
        startWakes()
        return true
    }

    func turnOff() {
        setOn(false)
        location.stopWakes()
        endCheck()
    }

    private func setOn(_ value: Bool) {
        isOn = value
        defaults.set(value, forKey: DetectionStore.enabledKey)
        if value { endOffer() }
    }

    private func startWakes() {
        location.startWakes { [weak self] fix in
            _ = await self?.wake(fix)
        }
    }

    // MARK: The offer

    /// A ride reached your stop: the first time, the offer is due (unless the switch is already on).
    func rideReachedYourStop() {
        guard !offered, !isOn, !offerDue else { return }
        offerDue = true
        defaults.set(true, forKey: DetectionStore.offerDueKey)
    }

    /// The offer showed: never again, whatever the answer.
    func offerShown() {
        endOffer()
    }

    private func endOffer() {
        offered = true
        offerDue = false
        defaults.set(true, forKey: DetectionStore.offeredKey)
        defaults.removeObject(forKey: DetectionStore.offerDueKey)
    }

    // MARK: Wake-ups

    /// A significant-change wake-up: a check starts, or the app sleeps again.
    @discardableResult
    func wake(_ fix: WakeFix) async -> Wake {
        refresh()
        guard isOn, location.allowsAlways else { return .off }
        let now = clock.now
        guard !Self.isQuiet(at: now) else { return .quietHours }
        guard !isChecking, !isRiding(), !isInForeground() else { return .busy }
        guard let route = route() else { return .noRoute }
        guard Self.isMoving(fix) else { return .standing }
        let trains = await candidates.candidates(on: route, at: now)
        guard Self.isNear(fix, trains) else { return .awayFromLine }
        guard isOn, !isChecking, !isRiding(), !isInForeground() else { return .busy }
        await startCheck(on: route, at: now)
        return .check
    }

    /// The app came to the front: Schedule's own detection takes over (D68), so a check stops.
    func appDidBecomeActive() {
        endCheck()
    }

    /// The check's timer: the matcher's, then the question, or the end at 12 minutes, at 1 AM, when a ride starts or when
    /// the app comes to the front.
    func tick() async {
        guard isChecking, let detector else { return }
        if postIfAsking(detector) { return }
        guard isOn, !isRiding(), !isInForeground(), let deadline, clock.now < deadline else { return endCheck() }
        await detector.tick()
        _ = postIfAsking(detector)
    }

    private func startCheck(on route: Route, at now: Date) async {
        let detector = makeDetector()
        self.detector = detector
        isChecking = true
        deadline = Self.deadline(from: now)
        guard await detector.start(on: route), self.detector === detector else {
            if self.detector === detector { endCheck() }
            return
        }
        guard let tickInterval else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: tickInterval)
                guard !Task.isCancelled, let self, self.isChecking else { return }
                await self.tick()
            }
        }
    }

    /// The matcher asks: the notification goes out, and the check ends. The question's trains are silenced at once, as an
    /// unanswered question silences them in the app (D68), so neither this nor Schedule asks about them again today.
    private func postIfAsking(_ detector: TrainDetector) -> Bool {
        guard case .asking(let question) = detector.state else { return false }
        notifier.post(question)
        detector.decline()
        endCheck()
        return true
    }

    private func endCheck() {
        loop?.cancel()
        loop = nil
        detector?.stop()
        detector = nil
        deadline = nil
        if isChecking { isChecking = false }
    }

    // MARK: Not me

    /// Not me on the notification: its trains are not asked about again today, and the third in a week turns the switch
    /// off. The notification's handler writes it with `DetectionStore` and calls `refresh()`; this is the same in one call.
    func notMe(_ train: DetectedTrain) {
        DetectionStore.recordNotMe(train, in: defaults, at: clock.now)
        refresh()
    }

    // MARK: Rules

    /// From 1 AM to 5 AM, Toronto time, nothing runs.
    static func isQuiet(at date: Date) -> Bool {
        quietHours.contains(calendar.component(.hour, from: date))
    }

    /// Moving, or the wake-up gives no speed (it comes after the phone moved about 500 m).
    static func isMoving(_ fix: WakeFix) -> Bool {
        fix.speed < 0 || fix.speed >= TrainMatcher.stoppedSpeed
    }

    /// Within 300 m of the track of one of the trains, counting a coarse fix's accuracy up to 1 km.
    static func isNear(_ fix: WakeFix, _ trains: [TrainCandidate]) -> Bool {
        guard fix.horizontalAccuracy >= 0 else { return false }
        let reach = lineReach + min(fix.horizontalAccuracy, accuracySlack)
        return trains.contains { train in
            guard let shape = train.plan.track?.shape else { return false }
            return shape.project(fix.coordinate).off <= reach
        }
    }

    /// 12 minutes after the start, or 1 AM if that comes first.
    static func deadline(from start: Date) -> Date {
        let end = start.addingTimeInterval(checkDuration)
        let quiet = calendar.nextDate(
            after: start, matching: DateComponents(hour: quietHours.lowerBound, minute: 0, second: 0), matchingPolicy: .nextTime
        )
        return quiet.map { min($0, end) } ?? end
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = goTimeZone
        return calendar
    }
}
