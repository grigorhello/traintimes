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

    static func model(
        _ rules: AlertRules, updates: AlertUpdates? = nil, nextTrains: (any NextTrainsProviding)? = nil,
        actionDuration: Duration = .seconds(60)
    ) async -> AlertsViewModel {
        var resolved = updates
        if resolved == nil { resolved = await self.updates([]) }
        return AlertsViewModel(
            rules: rules, updates: resolved!, nextTrains: nextTrains ?? NoNextTrains(), clock: FixedClock(now: now),
            actionDuration: actionDuration
        )
    }

    /// Today's 7:00 (gone at 7:21), 7:32, 7:58, 8:21 and 9:05 AM trains, Oakville to Union.
    static let nextTrains = FakeNextTrains(
        route: oakvilleToUnion,
        trips: [
            AlertFixtures.trip("LW-0700-20261105", departure: "12:00"), AlertFixtures.trip("LW-0732-20261105", departure: "12:32"),
            AlertFixtures.trip("LW-0758-20261105", departure: "12:58"), AlertFixtures.trip("LW-0821-20261105", departure: "13:21"),
            AlertFixtures.trip("LW-0905-20261105", departure: "14:05"),
        ]
    )
}

/// Today's trains for the empty Alerts tab, without a Schedule view model (TT-193).
@MainActor
final class FakeNextTrains: NextTrainsProviding {
    let nextTrains: (route: Route, trips: [Trip])?

    init(route: Route, trips: [Trip]) {
        nextTrains = (route, trips)
    }
}
