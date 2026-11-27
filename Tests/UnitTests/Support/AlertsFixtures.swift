import Foundation
@testable import TrainTimes

/// The Alerts tab's test values (TT-143, TT-193), as in design/frames/alerts.png, on the fixture clock (Thu Nov 5, 7:21 AM).
@MainActor
enum AlertsFixtures {
    static let now = try! Date("2026-11-05T12:21:00Z", strategy: .iso8601)

    static let oakvilleToUnion = AlertFixtures.route
    static let unionToOakville = AlertFixtures.route(("UN", "Union"), ("OA", "Oakville"))
    static let burlingtonToUnion = AlertFixtures.route(("BU", "Burlington"), ("UN", "Union"))

    /// 7:32 AM · Oakville to Union, Mon to Fri.
    static let morning = AlertRule(
        id: "morning", kind: .repeating, trip: AlertFixtures.trip(), route: oakvilleToUnion, weekdays: [1, 2, 3, 4, 5]
    )
    /// 5:10 PM · Union to Oakville, Mon to Thu, paused.
    static let evening = AlertRule(
        id: "evening", kind: .repeating, trip: AlertFixtures.trip("LW-1710-20261105", departure: "22:10"), route: unionToOakville,
        weekdays: [1, 2, 3, 4], paused: true
    )
    /// 8:05 AM · Burlington to Union, Mon to Fri; the server says its usual train has changed.
    static let burlington = AlertRule(
        id: "burlington", kind: .repeating, trip: AlertFixtures.trip("LW-0805-20261105", departure: "13:05"), route: burlingtonToUnion,
        weekdays: [1, 2, 3, 4, 5]
    )
    /// 8:21 AM · Oakville to Union, today only.
    static let today = AlertRule(
        id: "today", kind: .thisTrip, trip: AlertFixtures.trip("LW-0821-20261105", departure: "13:21"), route: oakvilleToUnion
    )

    static func update(
        _ id: String, kind: AlertUpdate.Kind = .delay, title: String, body: String, at time: String, tripId: String, serviceDate: String
    ) -> AlertUpdate {
        AlertUpdate(
            id: id, kind: kind, title: title, body: body, deliveredAt: try! Date(time, strategy: .iso8601), tripId: tripId,
            serviceDate: serviceDate, originId: "OA", destinationId: "UN"
        )
    }

    /// The frame's two updates: today's delay and yesterday's recovery.
    static let updates = [
        update(
            "delay", title: "7:32 AM train delayed 9 min", body: "Oakville to Union. Now expected 7:41 AM, as reported at 7:14 AM.",
            at: "2026-11-05T12:29:00Z", tripId: "LW-0732-20261105", serviceDate: "20261105"
        ),
        update(
            "recovery", kind: .recovery, title: "5:10 PM train back on time",
            body: "Union to Oakville. Expected 5:10 PM, as reported at 4:48 PM.", at: "2026-11-04T21:48:00Z",
            tripId: "LW-1710-20261104", serviceDate: "20261104"
        ),
    ]

    static let notice = LineNotice(
        id: "notice-1", lineName: "Lakeshore West", text: "Delays of up to 15 min near Port Credit",
        reportedAt: try! Date("2026-11-05T12:12:00Z", strategy: .iso8601)
    )

    /// Rules saved on the fake server, each in the state the test asks for.
    static func rules(
        _ server: FakeAlertServer, permission: NotificationPermission = .allowed, on: [AlertRule] = [], reviewNeeded: [AlertRule] = [],
        couldNotSave: [AlertRule] = []
    ) async -> AlertRules {
        let rules = AlertFixtures.rules(server, permission: permission)
        for rule in on + reviewNeeded { await rules.save(rule) }
        await server.setFailing(true)
        for rule in couldNotSave { await rules.save(rule) }
        await server.setFailing(false)
        await server.setStatuses(reviewNeeded.map { AlertRuleStatus(id: $0.id, state: .reviewNeeded) })
        await rules.refresh()
        return rules
    }

    static func updates(_ list: [AlertUpdate] = updates) async -> AlertUpdates {
        let updates = AlertUpdates(source: FixedDeliveredNotifications(updates: list), clock: FixedClock(now: now), defaults: nil)
        await updates.refresh()
        return updates
    }

    /// The Alerts tab's model on the fixture clock (Thu Nov 5, 7:21 AM), reading `repository` (the cards' trains: `trains()`
    /// by default), loaded once unless `loads` is false.
    static func model(
        _ rules: AlertRules, repository: (any ScheduleRepository)? = nil, nextTrains: (any NextTrainsProviding)? = nil,
        clock: (any AppClock)? = nil, mayAlert: @escaping @MainActor (Trip, Route) async -> Bool = { _, _ in true },
        haptics: any HapticPlaying = FakeHaptics(), actionDuration: Duration = .seconds(60), loads: Bool = true
    ) async -> AlertsViewModel {
        let model = AlertsViewModel(
            rules: rules, repository: repository ?? trains(), nextTrains: nextTrains ?? NoNextTrains(),
            clock: clock ?? FixedClock(now: now), mayAlert: mayAlert, actionDuration: actionDuration, haptics: haptics
        )
        if loads { await model.load() }
        return model
    }

    /// A train of the cards' timetable on Thu Nov 5 at a Toronto time ("07:32"), 40 min long (31 from Union).
    static func train(_ id: String, _ time: String, minutes: Int = 40, platform: String? = nil, express: Bool = false) -> Trip {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        let departs = ServiceDay(year: 2026, month: 11, day: 5).date(hour: parts[0], minute: parts[1])
        return Trip(
            key: TripKey(serviceDay: ServiceDay(year: 2026, month: 11, day: 5), tripId: "\(id)-20261105"),
            scheduledDeparture: departs, scheduledArrival: departs.addingTimeInterval(TimeInterval(minutes * 60)),
            platform: platform.map { .published($0) } ?? .pending, tags: express ? [.express] : []
        )
    }

    /// The cards' timetable, the same Monday to Saturday: Oakville to Union in the morning, Union to Oakville in the
    /// evening, one Burlington train.
    static let timetable: [String: [Trip]] = [
        "OA>UN": [
            train("LW-0700", "07:00"), train("LW-0732", "07:32", platform: "2"), train("LW-0758", "07:58", express: true),
            train("LW-0821", "08:21", express: true), train("LW-0850", "08:50"), train("LW-1245", "12:45", minutes: 44),
        ],
        "UN>OA": [train("LW-1710", "17:10", minutes: 31, express: true), train("LW-1728", "17:28", minutes: 31)],
        "BU>UN": [train("LW-0805", "08:05", minutes: 52)],
    ]

    static func trains(live: [String: LiveSnapshot] = [:], failing: Bool = false) -> AlertTripsRepository {
        AlertTripsRepository(trips: timetable, live: live, failing: failing)
    }

    /// Today's live status for Oakville to Union as fetched at `at` (7:21 AM): the 7:32 on time at Platform 2, `delays` and
    /// `cancelled` by GO trip ("LW-0732"); offline with its last update 29 min before (6:52 AM).
    static func live(delays: [String: Int] = [:], cancelled: Set<String> = [], offline: Bool = false, at: Date = now) -> LiveSnapshot {
        var updates: [String: LiveTripUpdate] = [:]
        for trip in timetable["OA>UN"] ?? [] {
            let id = String(trip.key.tripId.prefix(7))
            let delay = delays[id] ?? 0
            updates[trip.key.tripId] = LiveTripUpdate(
                expectedDeparture: trip.scheduledDeparture.addingTimeInterval(TimeInterval(delay * 60)),
                expectedArrival: trip.scheduledArrival.addingTimeInterval(TimeInterval(delay * 60)),
                delayMinutes: delay, isCancelled: cancelled.contains(id), reportedAt: at.addingTimeInterval(-60)
            )
        }
        if offline {
            return LiveSnapshot(updatedAt: at.addingTimeInterval(-29 * 60), isOffline: true, updates: updates)
        }
        return LiveSnapshot(updatedAt: at.addingTimeInterval(-30), hasPlatformSource: true, updates: updates, platforms: ["LW-0732-20261105": "2"])
    }

    /// Today's 7:00 (gone at 7:21), 7:32, 7:58, 8:21 and 8:50 AM trains, Oakville to Union, as Schedule has them.
    static var nextTrains: FakeNextTrains {
        let live = live()
        let trips = timetable["OA>UN"] ?? []
        return FakeNextTrains(
            route: oakvilleToUnion,
            departures: Departure.resolve(trips, live: live, freshness: Freshness(live, now: now), isToday: true)
        )
    }
}

/// Today's trains for the empty Alerts tab, without a Schedule view model (TT-193).
@MainActor
final class FakeNextTrains: NextTrainsProviding {
    let nextTrains: (route: Route, departures: [Departure])?
    var shownRoute: Route?

    init(route: Route, departures: [Departure]) {
        nextTrains = (route, departures)
        shownRoute = route
    }
}

/// The Alerts cards' trains (TT-253): each route's trips of Thu Nov 5 on every day but Sunday, taken to that day with the
/// date in their trip id, as the fixture feed does; today's live status per route; or no timetable at all.
actor AlertTripsRepository: ScheduleRepository {
    private let tripList: [String: [Trip]]
    private var live: [String: LiveSnapshot]
    private var failing: Bool

    init(trips: [String: [Trip]], live: [String: LiveSnapshot] = [:], failing: Bool = false) {
        tripList = trips
        self.live = live
        self.failing = failing
    }

    func set(live: LiveSnapshot, for key: String) {
        self.live[key] = live
    }

    func setFailing(_ failing: Bool) {
        self.failing = failing
    }

    func trips(for route: Route, on day: ServiceDay) async throws -> [Trip] {
        if failing { throw URLError(.notConnectedToInternet) }
        guard day.isoWeekday != 7 else { return [] }
        let base = ServiceDay(year: 2026, month: 11, day: 5)
        let shift = TimeInterval(base.days(to: day) * 86_400)
        return (tripList["\(route.from.id)>\(route.to.id)"] ?? []).map { trip in
            Trip(
                key: TripKey(serviceDay: day, tripId: trip.key.tripId.replacingOccurrences(of: base.gtfsDate, with: day.gtfsDate)),
                scheduledDeparture: trip.scheduledDeparture.addingTimeInterval(shift),
                scheduledArrival: trip.scheduledArrival.addingTimeInterval(shift), platform: day == base ? trip.platform : .pending,
                tags: trip.tags
            )
        }
    }

    func liveStatus(for route: Route, on day: ServiceDay) async throws -> LiveSnapshot {
        live["\(route.from.id)>\(route.to.id)"] ?? .empty
    }

    func lineNotices(for line: Line) async throws -> [LineNotice] { [] }
}
