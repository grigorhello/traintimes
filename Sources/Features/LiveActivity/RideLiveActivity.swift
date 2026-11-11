import ActivityKit
import Foundation
import UIKit

/// The alerted train before it leaves, as the app sees it (TT-178): Schedule's live departure, or the demo departure's.
struct DepartureActivitySource {
    let live: LiveDeparture
    let route: Route
    /// Its clock: Mock time, or the demo departure's own.
    let now: Date
    let hasPlatformSource: Bool

    /// The ride a hand-off would start on this train: the activity's identity.
    var ride: Ride { Ride(trip: live.key, from: route.from.id, to: route.to.id) }
}

/// The ride on the Lock Screen and in the Dynamic Island (TT-174, D67), and before it the alerted train's countdown (TT-178,
/// D74). It follows the app's ride engine, or the demo ride's while Demo trains › Ride plays: it starts the activity when a
/// ride starts (only with the app in front, Apple's rule; a ride restored in the background gets its activity once the app
/// is opened), updates it when what it shows changes and at least once a minute, alerts once when the train is about a
/// minute from your stop, and ends it with the ride: 15 min after the train reached your stop, at once on End ride.
///
/// Before departure the alert server starts the activity with a push-to-start at T−30 (iOS 17.2+); the app in front starts
/// it itself when none came, keeps it up to date while it runs, and ends it 2 min after the train left. "I’m on board" turns
/// that same activity into the ride (the hand-off), and the app tells the server, which then sends nothing more. The app
/// sends the server its push-to-start token and each departure activity's update token. One per app, made by
/// `AppDelegate`; none in fixture runs (UI tests, the unit test host, previews), so nothing appears in the island while they
/// run.
@MainActor
final class RideLiveActivity: RideActivityFollowing {
    /// The activity greys itself this long after the app last updated it.
    static let staleAfter: TimeInterval = 2 * 60
    /// An update at least this often, so a running app keeps it fresh; under a minute, so the engine's minute tick on the
    /// timetable always sends one.
    static let refreshAfter: TimeInterval = 45
    /// The ended activity stays on the Lock Screen until this long after the train reached your stop (the engine ends the
    /// ride 10 min after it).
    static let lingersAfterArrival: TimeInterval = 15 * 60
    /// While the app is in front, the departure is looked at this often: its phases follow the clock, not the engine.
    static let departureTick: Duration = .seconds(2)
    /// With a push-to-start token the server starts the activity at T−30; the app in front waits this long for it, so the
    /// two do not cross.
    static let serverGrace: TimeInterval = 90

    private let app: RideEngine?
    private var demo: RideEngine?
    /// The ride's line, for the tile: the GO feed's, or the demo's.
    private let line: @MainActor (Ride) async -> Line?
    /// A ride's stops, for a departure's activity: made with the ride's stop count, so the hand-off keeps it.
    private let plan: @MainActor (Ride) async -> RidePlan?
    private let formatter: @MainActor () -> TimeFormatter
    /// The app is in front, where an activity can start.
    private let canStart: @MainActor () -> Bool
    /// Reports a departure activity before `connect` (a background launch): straight to the server, if the installation is
    /// registered there.
    private let backgroundReport: (@Sendable (LiveActivityReport) async -> Void)?

    private var isFollowing = false
    private var listener: Task<Void, Never>?
    private var isSyncing = false
    private var needsSync = false
    /// When the activity was last sent, to refresh it once a minute.
    private var sentAt: Date?
    /// The ride the activity was started for: one the rider swiped off the Lock Screen does not come back with the app.
    private var startedRide: Ride?
    /// The ride that has had its one alert, should the train fall back from arriving and come round to it again.
    private var alertedRide: Ride?

    // Before departure (TT-178)

    /// The live departure, once `RootView` connects.
    private var departures: (@MainActor () -> DepartureActivitySource?)?
    private var reporter: (any LiveActivityReporting)?
    /// The train whose departure has had an activity this window: one the rider swiped away does not come back.
    private var departureStarted: Ride?
    private var departureSentAt: Date?
    private var ticker: Task<Void, Never>?
    private var observesTokens = false
    /// The activities whose update tokens are followed.
    private var followedTokens: Set<String> = []
    /// The push-to-start token, hex; nil before iOS 17.2 or until iOS issues it.
    private var startToken: String?

    init(
        app: RideEngine?,
        line: @escaping @MainActor (Ride) async -> Line?,
        plan: @escaping @MainActor (Ride) async -> RidePlan? = { _ in nil },
        formatter: @escaping @MainActor () -> TimeFormatter,
        canStart: @escaping @MainActor () -> Bool,
        backgroundReport: (@Sendable (LiveActivityReport) async -> Void)? = nil
    ) {
        self.app = app
        self.line = line
        self.plan = plan
        self.formatter = formatter
        self.canStart = canStart
        self.backgroundReport = backgroundReport
    }

    /// The engine the activity shows: the demo's while it plays, else the app's.
    private var engine: RideEngine? { demo ?? app }

    /// At launch, once the app's ride is restored: from now on the activity follows it. An activity left from a ride that
    /// is over ends here. The tokens are followed from here too, so an activity the server started while the app was closed
    /// has its token reported even when iOS wakes the app in the background for it.
    func start() {
        isFollowing = true
        followTokens()
        listen()
    }

    /// The train of the departure activity on screen, for its tap and its "I’m on board" (TT-178).
    var departureRide: Ride? {
        Activity<RideActivityAttributes>.activities
            .first { $0.content.state.isDeparture && Self.isShowing($0.activityState) }
            .map { Ride($0.attributes) }
    }

    /// `RootView`: the live departure and the alert rules, which take the tokens to the server.
    func connect(reporter: any LiveActivityReporting, departures: @escaping @MainActor () -> DepartureActivitySource?) {
        self.reporter = reporter
        self.departures = departures
        if let startToken {
            Task { await self.reporter?.reportStartToken(startToken) }
        }
        sync()
    }

    /// Demo trains › Ride started or stopped (`OnBoard`).
    func follow(demo engine: RideEngine?) {
        guard engine !== demo else { return }
        demo = engine
        startedRide = nil
        alertedRide = nil
        if isFollowing { listen() }
    }

    /// The app came to the front: a ride restored in the background gets its activity now, and the departure is followed
    /// while the app stays in front.
    func sceneDidBecomeActive() {
        sync()
        guard ticker == nil else { return }
        ticker = Task {
            repeat {
                try? await Task.sleep(for: Self.departureTick)
                sync()
            } while canStart()
            ticker = nil
        }
    }

    private func listen() {
        listener?.cancel()
        listener = nil
        sync()
        guard let engine else { return }
        let events = engine.events()
        listener = Task { [weak self] in
            for await _ in events {
                guard !Task.isCancelled else { return }
                self?.sync()
            }
        }
    }

    /// Brings the activity in line with the engine, one pass at a time.
    private func sync() {
        guard isFollowing else { return }
        needsSync = true
        guard !isSyncing else { return }
        isSyncing = true
        Task {
            while needsSync {
                needsSync = false
                await reconcile()
            }
            isSyncing = false
        }
    }

    private func reconcile() async {
        let engine = engine
        let ride = engine?.ride
        let activities = Activity<RideActivityAttributes>.activities.filter { Self.isShowing($0.activityState) }
        // Another ride's activity (one that ended while the app was stopped, or the demo's) leaves at once.
        for id in activities.filter({ !$0.content.state.isDeparture && !$0.attributes.shows(ride) }).map(\.id) {
            await Self.end(id, content: nil, dismissal: nil)
        }
        if let engine, let ride, let plan = engine.plan, let state = engine.state {
            if state.phase != .ended {
                await reconcileRide(engine: engine, ride: ride, plan: plan, state: state, activities: activities)
                return
            }
            await endRide(engine: engine, ride: ride, plan: plan, state: state, activities: activities)
        }
        await reconcileDeparture(activities.filter { $0.content.state.isDeparture })
    }

    /// A ride runs: its activity, which may be the train's departure activity (the hand-off), else a new one.
    private func reconcileRide(
        engine: RideEngine, ride: Ride, plan: RidePlan, state: RideState, activities: [Activity<RideActivityAttributes>]
    ) async {
        // The ride wins over another train's countdown; this train's becomes the ride when its bar has the ride's stops.
        let fits = { (activity: Activity<RideActivityAttributes>) in
            activity.attributes.shows(ride) && (!activity.content.state.isDeparture || activity.attributes.stopCount == plan.stops.count)
        }
        for activity in activities where activity.content.state.isDeparture && !fits(activity) {
            await Self.end(activity.id, content: nil, dismissal: nil)
            // This train's, with another stop count: the ride gets its own activity, and the server leaves this one.
            if activity.attributes.shows(ride) { await report(LiveActivityReport(activity.attributes, handedOff: true)) }
        }
        let deviceNow = Date()
        guard let content = RideActivityAttributes.ContentState(
            plan: plan, state: state, now: engine.now, deviceNow: deviceNow, formatter: formatter()
        ) else { return }
        let current = activities.first(where: fits)
        let staleDate = deviceNow.addingTimeInterval(Self.staleAfter)
        if let current {
            let shown = current.content.state
            guard Self.needsUpdate(from: shown, to: content, sentAt: shown.isDeparture ? nil : sentAt, now: deviceNow) else { return }
            sentAt = deviceNow
            let alerts = Self.alerts(from: shown, to: content) && alertedRide != ride
            if alerts { alertedRide = ride }
            await Self.update(current.id, content: content, staleDate: staleDate, alerts: alerts)
            if shown.isDeparture {
                // The hand-off: the same activity now shows the ride, and the server leaves it to the app. Ended later,
                // the ride does not bring the countdown back.
                startedRide = ride
                departureStarted = ride
                await report(LiveActivityReport(current.attributes, handedOff: true))
            }
        } else {
            guard startedRide != ride, canStart(), ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            let line = await line(ride)
            // The ride may have moved on while the line was looked up; the next pass starts it then.
            guard engine.ride == ride, engine.state?.phase != .ended,
                  !Activity<RideActivityAttributes>.activities.contains(where: { $0.attributes.shows(ride) && Self.isShowing($0.activityState) })
            else { return }
            do {
                _ = try Activity.request(
                    attributes: RideActivityAttributes(ride: ride, plan: plan, line: line),
                    content: ActivityContent(state: content, staleDate: staleDate)
                )
                sentAt = deviceNow
                startedRide = ride
                if content.isAlert { alertedRide = ride }
            } catch {
                // Live Activities are off for the app, or it went to the background: the next pass in front tries again.
            }
        }
    }

    /// The ride ended: its activity ends with it, staying on the Lock Screen a while after an arrival.
    private func endRide(
        engine: RideEngine, ride: Ride, plan: RidePlan, state: RideState, activities: [Activity<RideActivityAttributes>]
    ) async {
        // The same trip can be ridden again: it gets a new activity and a new alert.
        startedRide = nil
        alertedRide = nil
        let deviceNow = Date()
        guard let current = activities.first(where: { !$0.content.state.isDeparture && $0.attributes.shows(ride) }),
              let content = RideActivityAttributes.ContentState(
                  plan: plan, state: state, now: engine.now, deviceNow: deviceNow, formatter: formatter()
              )
        else { return }
        sentAt = nil
        await Self.end(current.id, content: content, dismissal: Self.dismissal(for: state, engineNow: engine.now, deviceNow: deviceNow))
    }

    /// No ride runs: the alerted train's countdown (TT-178). Whoever started it, it ends 2 min after the train left (its
    /// stale date); the app keeps the live departure's up to date and starts it when none came.
    private func reconcileDeparture(_ activities: [Activity<RideActivityAttributes>]) async {
        let deviceNow = Date()
        var current: [Activity<RideActivityAttributes>] = []
        for activity in activities {
            if let stale = activity.content.staleDate, stale <= deviceNow {
                await Self.end(activity.id, content: nil, dismissal: nil)
            } else {
                current.append(activity)
            }
        }
        guard let source = departures?() else { return }
        let ride = source.ride
        if departureStarted != ride { departureStarted = nil }
        let content = RideActivityAttributes.ContentState(
            departure: source.live, origin: source.route.from.name, destination: source.route.to.name,
            hasPlatformSource: source.hasPlatformSource, now: source.now, deviceNow: deviceNow, formatter: formatter()
        )
        let staleDate = Self.departureStaleDate(source.live, now: source.now, deviceNow: deviceNow)
        let mine = current.filter { $0.attributes.shows(ride) }
        if let shown = mine.first {
            departureStarted = ride
            // The server's start and the app's crossed: one stays, and its token is the one the server updates.
            for extra in mine.dropFirst() {
                await Self.end(extra.id, content: nil, dismissal: nil)
            }
            if mine.count > 1, let token = shown.pushToken {
                await report(LiveActivityReport(shown.attributes, token: Self.hex(token)))
            }
            guard Self.needsUpdate(from: shown.content.state, to: content, sentAt: departureSentAt, now: deviceNow) else { return }
            departureSentAt = deviceNow
            await Self.update(shown.id, content: content, staleDate: staleDate, alerts: false)
            return
        }
        // Started by the app in front, once a window, and not once the train has left.
        guard departureStarted != ride, source.live.phase != .departed, canStart(),
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if startToken != nil, source.live.leaves.timeIntervalSince(source.now) > LiveDeparture.window - Self.serverGrace { return }
        guard let plan = await plan(ride), plan.stops.count >= 2 else { return }
        let line = await line(ride)
        guard departures?()?.ride == ride,
              !Activity<RideActivityAttributes>.activities.contains(where: { $0.attributes.shows(ride) && Self.isShowing($0.activityState) })
        else { return }
        let attributes = RideActivityAttributes(ride: ride, plan: plan, line: line)
        let activityContent = ActivityContent(state: content, staleDate: staleDate)
        // With an update token the server can update and end it once the app is closed.
        guard let activity = (try? Activity.request(attributes: attributes, content: activityContent, pushType: .token))
            ?? (try? Activity.request(attributes: attributes, content: activityContent))
        else { return }
        departureStarted = ride
        departureSentAt = deviceNow
        followToken(of: activity.id)
        await report(LiveActivityReport(attributes))
    }

    // MARK: Tokens (TT-178)

    /// The push-to-start token (iOS 17.2+), new activities (the server's starts) and each departure activity's update token.
    private func followTokens() {
        guard !observesTokens else { return }
        observesTokens = true
        if #available(iOS 17.2, *) {
            Task {
                await Self.startTokens { [weak self] token in await self?.received(startToken: token) }
            }
        }
        Task {
            await Self.newActivities { [weak self] id in await self?.followToken(of: id) }
        }
        for activity in Activity<RideActivityAttributes>.activities {
            followToken(of: activity.id)
        }
    }

    private func received(startToken token: String) async {
        startToken = token
        await reporter?.reportStartToken(token)
    }

    private func followToken(of id: String) {
        guard followedTokens.insert(id).inserted else { return }
        Task {
            await Self.pushTokens(of: id) { [weak self] token in await self?.received(token: token, of: id) }
        }
    }

    /// A departure activity's update token goes to the server; a ride's is not needed (the app updates the ride).
    private func received(token: String, of id: String) async {
        guard let activity = Activity<RideActivityAttributes>.activities.first(where: { $0.id == id }),
              activity.content.state.isDeparture else { return }
        await report(LiveActivityReport(activity.attributes, token: token))
    }

    private func report(_ activity: LiveActivityReport) async {
        if let reporter {
            await reporter.report(activity)
        } else {
            await backgroundReport?(activity)
        }
    }

    // MARK: ActivityKit

    // An `Activity` is not Sendable, so its async calls run off the main actor, on an activity looked up there by id.

    private nonisolated static func update(
        _ id: String, content: RideActivityAttributes.ContentState, staleDate: Date, alerts: Bool
    ) async {
        guard let activity = Activity<RideActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        let alert = alerts
            ? AlertConfiguration(
                title: LocalizedStringResource(stringLiteral: content.title),
                body: LocalizedStringResource(stringLiteral: content.detail),
                sound: .default
            )
            : nil
        await activity.update(ActivityContent(state: content, staleDate: staleDate), alertConfiguration: alert)
    }

    /// Ends the activity with its last content, leaving the Lock Screen at `dismissal`, or at once with none.
    private nonisolated static func end(_ id: String, content: RideActivityAttributes.ContentState?, dismissal: Date?) async {
        guard let activity = Activity<RideActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.end(
            content.map { ActivityContent(state: $0, staleDate: nil) },
            dismissalPolicy: dismissal.map { .after($0) } ?? .immediate
        )
    }

    @available(iOS 17.2, *)
    private nonisolated static func startTokens(_ received: @escaping @Sendable (String) async -> Void) async {
        for await token in Activity<RideActivityAttributes>.pushToStartTokenUpdates {
            await received(hex(token))
        }
    }

    private nonisolated static func newActivities(_ found: @escaping @Sendable (String) async -> Void) async {
        for await activity in Activity<RideActivityAttributes>.activityUpdates {
            await found(activity.id)
        }
    }

    private nonisolated static func pushTokens(of id: String, _ received: @escaping @Sendable (String) async -> Void) async {
        guard let activity = Activity<RideActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        for await token in activity.pushTokenUpdates {
            await received(hex(token))
        }
    }

    // MARK: The rules

    private nonisolated static func isShowing(_ state: ActivityState) -> Bool {
        state == .active || state == .stale
    }

    /// An APNs token as the server keeps it: lowercase hex.
    nonisolated static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    /// Something a rider would see changed, or the last update is a minute old.
    static func needsUpdate(
        from shown: RideActivityAttributes.ContentState, to next: RideActivityAttributes.ContentState, sentAt: Date?, now: Date
    ) -> Bool {
        guard let sentAt, now.timeIntervalSince(sentAt) < refreshAfter else { return true }
        return !shown.looksLike(next)
    }

    /// The one alert of a ride: the train is now about a minute from your stop.
    static func alerts(from shown: RideActivityAttributes.ContentState, to next: RideActivityAttributes.ContentState) -> Bool {
        next.phase == .arriving && shown.phase != .arriving
    }

    /// When an ended ride's activity leaves the Lock Screen, on the device clock: 15 min after the train reached your stop
    /// for a ride that ended there; nil (at once) for End ride, a cancelled trip, leaving the line, or when that time has
    /// passed.
    static func dismissal(for state: RideState, engineNow: Date, deviceNow: Date) -> Date? {
        guard state.endReason == .arrived else { return nil }
        let leaves = deviceNow.addingTimeInterval(state.expectedArrival.addingTimeInterval(lingersAfterArrival).timeIntervalSince(engineNow))
        return leaves > deviceNow ? leaves : nil
    }

    /// A departure's activity goes stale, and ends, 2 min after the train left, on the device clock (the server sets the
    /// same stale date).
    static func departureStaleDate(_ live: LiveDeparture, now: Date, deviceNow: Date) -> Date {
        deviceNow.addingTimeInterval(live.leaves.addingTimeInterval(LiveDeparture.departedFor).timeIntervalSince(now))
    }
}

extension LiveActivityReport {
    /// The activity's train, as the server keys its watch.
    init(_ attributes: RideActivityAttributes, token: String? = nil, handedOff: Bool = false) {
        self.init(
            tripId: attributes.tripId, serviceDate: String(attributes.serviceDate), originId: attributes.originId,
            destinationId: attributes.destinationId, token: token, handedOff: handedOff
        )
    }
}

extension Ride {
    /// The ride an activity shows.
    init(_ attributes: RideActivityAttributes) {
        self.init(
            trip: TripKey(serviceDay: ServiceDay(dateKey: attributes.serviceDate), tripId: attributes.tripId),
            from: attributes.originId, to: attributes.destinationId
        )
    }
}

extension RideLiveActivity {
    /// The app's: the GO feed's lines and stops and the Time format setting. Nil in fixture runs.
    static func app(following ride: RideEngine, environment: [String: String] = ProcessInfo.processInfo.environment) -> RideLiveActivity? {
        guard !ScheduleDependencies.isFixtureRun(environment) else { return nil }
        let stations = ScheduleDependencies.app(environment: environment).stations
        return RideLiveActivity(
            app: ride,
            line: { ride in
                if ride.tripId == DemoRide.tripId { return DemoRide.line }
                guard let all = try? await stations.stations(),
                      let from = all.first(where: { $0.id == ride.originId }),
                      let to = all.first(where: { $0.id == ride.destinationId }) else { return nil }
                return try? await stations.route(from: from, to: to).line
            },
            plan: { [ride] trip in
                if trip.tripId == DemoRide.tripId { return DemoRide.plan(on: trip.tripKey.serviceDay) }
                return await ride.plan(for: trip)
            },
            formatter: {
                let stored = UserDefaults.standard.string(forKey: AppSettings.timeFormatKey).flatMap(TimeFormat.init(rawValue:))
                return TimeFormatter(format: stored ?? .device)
            },
            canStart: { UIApplication.shared.applicationState == .active },
            backgroundReport: { report in
                // Only an installation the server knows: it registered with the rider's first alert.
                guard let installation = UserDefaults.standard.string(forKey: AlertRules.installationKey) else { return }
                try? await HTTPAlertServer().report(report, installation: installation)
            }
        )
    }
}
