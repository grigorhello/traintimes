import ActivityKit
import Foundation
import UIKit

/// The ride on the Lock Screen and in the Dynamic Island (TT-174, D67). It follows the app's ride engine, or the demo ride's
/// while Demo trains › Ride plays: it starts the activity when a ride starts (only with the app in front, Apple's rule; a
/// ride restored in the background gets its activity once the app is opened), updates it when what it shows changes and at
/// least once a minute, alerts once when the train is about a minute from your stop, and ends it with the ride: 15 min
/// after the train reached your stop, at once on End ride. One per app, made by `AppDelegate`; none in fixture runs (UI
/// tests, the unit test host, previews), so nothing appears in the island while they run.
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

    private let app: RideEngine?
    private var demo: RideEngine?
    /// The ride's line, for the tile: the GO feed's, or the demo's.
    private let line: @MainActor (Ride) async -> Line?
    private let formatter: @MainActor () -> TimeFormatter
    /// The app is in front, where an activity can start.
    private let canStart: @MainActor () -> Bool

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

    init(
        app: RideEngine?,
        line: @escaping @MainActor (Ride) async -> Line?,
        formatter: @escaping @MainActor () -> TimeFormatter,
        canStart: @escaping @MainActor () -> Bool
    ) {
        self.app = app
        self.line = line
        self.formatter = formatter
        self.canStart = canStart
    }

    /// The engine the activity shows: the demo's while it plays, else the app's.
    private var engine: RideEngine? { demo ?? app }

    /// At launch, once the app's ride is restored: from now on the activity follows it. An activity left from a ride that
    /// is over ends here.
    func start() {
        isFollowing = true
        listen()
    }

    /// Demo trains › Ride started or stopped (`OnBoard`).
    func follow(demo engine: RideEngine?) {
        guard engine !== demo else { return }
        demo = engine
        startedRide = nil
        alertedRide = nil
        if isFollowing { listen() }
    }

    /// The app came to the front: a ride restored in the background gets its activity now.
    func sceneDidBecomeActive() {
        sync()
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
        for id in activities.filter({ !$0.attributes.shows(ride) }).map(\.id) {
            await Self.end(id, content: nil, dismissal: nil)
        }
        guard let engine, let ride, let plan = engine.plan, let state = engine.state else { return }
        let deviceNow = Date()
        guard let content = RideActivityAttributes.ContentState(
            plan: plan, state: state, now: engine.now, deviceNow: deviceNow, formatter: formatter()
        ) else { return }
        let current = activities.first { $0.attributes.shows(ride) }
        let currentId = current?.id
        let shown = current?.content.state

        if state.phase == .ended {
            // The same trip can be ridden again: it gets a new activity and a new alert.
            startedRide = nil
            alertedRide = nil
            guard let currentId else { return }
            sentAt = nil
            await Self.end(currentId, content: content, dismissal: Self.dismissal(for: state, engineNow: engine.now, deviceNow: deviceNow))
            return
        }

        let staleDate = deviceNow.addingTimeInterval(Self.staleAfter)
        if let currentId, let shown {
            guard Self.needsUpdate(from: shown, to: content, sentAt: sentAt, now: deviceNow) else { return }
            sentAt = deviceNow
            let alerts = Self.alerts(from: shown, to: content) && alertedRide != ride
            if alerts { alertedRide = ride }
            await Self.update(currentId, content: content, staleDate: staleDate, alerts: alerts)
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

    // MARK: The rules

    private nonisolated static func isShowing(_ state: ActivityState) -> Bool {
        state == .active || state == .stale
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
}

extension RideLiveActivity {
    /// The app's: the GO feed's lines and the Time format setting. Nil in fixture runs.
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
            formatter: {
                let stored = UserDefaults.standard.string(forKey: AppSettings.timeFormatKey).flatMap(TimeFormat.init(rawValue:))
                return TimeFormatter(format: stored ?? .device)
            },
            canStart: { UIApplication.shared.applicationState == .active }
        )
    }
}
